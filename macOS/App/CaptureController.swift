import AppKit
import ApplicationServices
import KeyboardShortcuts
import OSLog
import ResponsayCore

/// macOS glue for Surface A: owns the view model, the overlay panels, and the
/// target-app tracker; wires the global toggle hotkey; plays the start cue; and
/// applies user preferences. Keeps the SwiftUI `App` thin.
@MainActor
final class CaptureController {
    let vm: QuickCaptureViewModel
    private let panel: CapsulePanel
    /// #576: the AppKit status bar (icon + menu) — created in start(), replaces MenuBarExtra.
    private var statusItemController: StatusItemController?
    let voiceAssistantVM: VoiceAssistantViewModel
    private let voiceAssistantPanel: VoiceAssistantPanel

    let targetTracker = TargetAppTracker()
    private let selectionReader = SelectionTextReader(
        axReader: { target in
            let reader = AccessibilityContextReader()
            return reader.readContext(from: target).selectedText
        },
        menuActionCopier: { target in
            await MenuActionCopier.copy(from: target)
        },
        clipboardCopier: { target in
            await ClipboardCopier.copy(from: target)
        }
    )
    let contextReader: AccessibilityContextReader
    private let gateContextReader: CaptureGateContextReader
    /// 434 — auto-learn flywheel: snapshots the field after insertion, learns from the user's edits.
    private let autoLearnController: HotwordAutoLearnController
    let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "controller")
    let shortcutSettingsStore = ShortcutSettingsStore.shared
    /// Hotkey registration + dispatch (Fn / 右 Option anchors, ⌃/⌘ combos, normal slots). Routes
    /// resolved commands into `hotkeyRouter`; the router stays here because its handlers reference the
    /// 6 sub-controllers. Internal (not private) so `CaptureController+ShortcutDebug` can drive
    /// `handleFnChord` under DEBUG. `lazy` (like the other sub-controllers) so it can capture `self`.
    lazy var hotkeyDispatcher = HotkeyDispatcher(
        shortcutSettingsStore: shortcutSettingsStore,
        route: { [weak self] phase, action, trigger in
            self?.hotkeyRouter.handle(phase, action: action, trigger: trigger)
        },
        log: log)
    /// OS-event lifecycle interrupts: defaults-change re-sync, sleep/wake recovery, global Esc abort.
    private lazy var stateOrchestrator = StateOrchestrator(
        reSyncHotkeys: { [weak self] in self?.hotkeyDispatcher.syncFnMonitor() },
        cancelCapture: { [weak self] in await self?.vm.cancelCapture() },
        handleEscape: { [weak self] in await self?.escapeController.handleEscape() })

    lazy var speechController = CaptureSpeechController(
        vm: vm,
        targetTracker: targetTracker,
        log: log,
        textModelPreflight: { [weak self] outputMode in
            self?.requireTextModelIfNeeded(outputMode: outputMode) ?? false
        })
    private lazy var selectionController = CaptureSelectionController(
        vm: vm,
        targetTracker: targetTracker,
        selectionReader: selectionReader,
        log: log,
        legalBrainEnabled: { Self.legalBrainEnabled },
        textModelPreflight: { [weak self] outputMode in
            self?.requireTextModelIfNeeded(outputMode: outputMode) ?? false
        },
        // 划词翻译: replace in editable fields, preview card when the focused field is read-only.
        isTargetEditable: { [weak self] in
            guard let self else { return false }
            return self.contextReader.isFocusedElementEditable(from: self.targetTracker.target)
        },
        // Seed the VA from a selection; the panel surfaces it and the 任意提问 hotkey drives the
        // turns. 任意提问 = open chat; 反方观点对抗 = 对抗 mode (审稿人加压→作者回应).
        onSelectionAsk: { [weak self] sel in self?.voiceAssistantVM.beginSelectionAsk(selection: sel) },
        onCounterargumentDebate: { [weak self] subject in
            self?.voiceAssistantVM.beginDebate(subject: subject, script: .counterargument)
        })
    private lazy var snapOCRController = CaptureSnapOCRController(vm: vm, log: log)
    private lazy var diagnosticsController = CaptureDiagnosticsController(
        vm: vm,
        targetTracker: targetTracker,
        contextReader: contextReader,
        selectionReader: selectionReader,
        log: log,
        noteAutoLearnInsertion: { [weak self] in
            self?.autoLearnController.noteInsertion()
        })
    private lazy var askAnythingController = CaptureAskAnythingController(
        isListening: { [weak self] in self?.voiceAssistantVM.phase == .listening },
        startSession: { [weak self] in self?.startAskAnythingSession() },
        stopSession: { [weak self] in self?.stopAskAnythingSession() })
    /// Esc routes to cancellation (not submit): discard the dictation audio, or drop the current
    /// 任意提问 question without sending it to the LLM. Plays the stop cue on either cancel.
    private lazy var escapeController = CaptureEscapeController(
        isCaptureListening: { [weak self] in self?.vm.phase == .listening },
        cancelCapture: { [weak self] in
            guard let self else { return }
            self.speechController.playConfiguredStopCue()
            await self.vm.cancelCapture()
        },
        isAskAnythingListening: { [weak self] in self?.voiceAssistantVM.phase == .listening },
        cancelAskAnything: { [weak self] in
            guard let self else { return }
            await self.cancelAskAnythingSession()
        })

    lazy var hotkeyRouter = HotkeyActionRouter(
        handlers: HotkeyActionHandlers(
            isHoldToTalkEnabled: { [weak self] in
                self?.speechController.isHoldToTalkEnabled ?? false
            },
            beginCapture: { [weak self] action, trigger in
                if self?.voiceAssistantVM.phase == .listening {
                    self?.askAnythingController.handleDown(trigger: trigger)
                    return
                }
                // 434 — before starting a new capture, re-read the field: if the user edited the
                // last insertion, that's the correction to learn from.
                self?.autoLearnController.checkForCorrection()
                self?.speechController.beginCaptureFromHotkey(action, trigger: trigger)
            },
            finishCurrentHotkeyAction: { [weak self] trigger in
                self?.speechController.finishCurrentHotkeyAction(trigger: trigger)
            },
            rewriteSelection: { [weak self] in
                self?.rewriteSelection()
            },
            translateSelection: { [weak self] in
                self?.translateSelection()
            },
            snapOCR: { [weak self] in
                self?.snapOCR()
            },
            snapTextOCR: { [weak self] in
                self?.snapTextOCR()
            },
            snapImageCopy: { [weak self] in
                self?.snapImageCopy()
            },
            showSelectionMenu: { [weak self] in
                self?.selectionController.showSelectionMenuFromHotkey()
            },
            beginAskAnything: { [weak self] trigger in self?.askAnythingController.handleDown(trigger: trigger) },
            finishAskAnything: { [weak self] trigger in self?.askAnythingController.handleUp(trigger: trigger) },
            openApp: { MainWindowController.shared.show() },
            openSettings: { MacSettingsWindowController.shared.show() },
            confirmInsert: { [weak self] in
                self?.confirmInsert()
            }
        )
    )

    /// 112: the legal subsystem is gated behind `LegalBrainEnabled` (default on for
    /// internal/DEBUG testers, off for release). Off → no runtime, no legal skills run;
    /// the app behaves exactly as the dictation product.
    static var legalBrainEnabled: Bool {
        LegalBrainFlag.resolve(
            stored: UserDefaults.standard.object(forKey: LegalBrainFlag.defaultsKey) as? Bool
        ).isEnabled
    }

    init() {
        let tracker = targetTracker
        self.voiceAssistantVM = VoiceAssistantViewModel(speech: RoutedSpeechCaptureService())
        // 重新生成 from the answer card re-streams via a freshly-resolved endpoint — the same
        // 任意提问 chat path as stopAskAnythingSession (resolveChat, honoring the 思考 toggle), so
        // the card never has to hold an LLM client itself.
        self.voiceAssistantVM.makeClient = {
            let endpoint = LLMEndpointResolver.resolveChat()
            let searchEnabled = VoiceAssistantWebSearchSettings.effectiveEnabled(endpoint: endpoint)
            return endpoint.map { DirectStreamingChatClient(endpoint: $0, searchEnabled: searchEnabled) }
        }
        self.voiceAssistantPanel = VoiceAssistantPanel(vm: self.voiceAssistantVM)
        self.voiceAssistantPanel.start()

        let reader = AccessibilityContextReader()
        contextReader = reader
        let gateReader = CaptureGateContextReader()
        gateContextReader = gateReader
        let autoLearn = HotwordAutoLearnController(snapshotReader: { reader.readFocusedFieldSnapshot(from: tracker.target) })
        autoLearnController = autoLearn
        let legalStore = try? SQLiteLegalProfileStore.defaultStore()
        let rawInserter = CGEventTextInserter(targetProvider: { tracker.target })
        // 434 — after a dictation insert lands, snapshot the field so we can learn from any edit.
        // CGEvent insertion is asynchronous, so settle briefly before reading it back.
        let dictationInserter = NotifyingTextInserter(wrapping: rawInserter) { [weak autoLearn, reader] insertedText in
            Task { @MainActor in
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(200))
                    if reader.readFocusedFieldSnapshot(from: tracker.target)?.text.contains(insertedText) == true { break }
                }
                autoLearn?.noteInsertion()
                // Style learning (P1): after a dictation lands, maybe re-distill the user's style
                // (gated: enabled, ≤ once/day, ≥ min samples) so 意图成稿 keeps sounding like them.
                StyleProfileRefresher.scheduleIfNeeded()
            }
        }
        // Revert AI (P0b): swap the just-inserted AI text back to the raw transcript, then re-baseline
        // the auto-learn watcher so the polished→raw change isn't mistaken for a user correction.
        let reverter = InsertionReverter(
            targetProvider: { tracker.target },
            rawInserter: rawInserter,
            onReverted: { [weak autoLearn] in autoLearn?.noteInsertion() })
        // 560: the Intent-aware safe-undo executor — deletes the verified text or restores the
        // replaced selection via a precise AX value write; refuses (never a caret-relative guess)
        // when the field isn't AX-settable. Never writes the raw transcript back. Real-host behavior
        // (native / web / Electron) is HITL-verified in #568.
        let intentReverter = IntentInsertionReverter(targetProvider: { tracker.target })
        vm = QuickCaptureViewModel(
            speech: RoutedSpeechCaptureService(),
            coach: SettingsBackedCoachAPI(),
            store: Self.makeCaptureStore(),
            inserter: dictationInserter,
            textCoach: SettingsBackedCoachAPI(),
            polisher: SettingsBackedTextPolishAPI(),
            punctuator: SettingsBackedLocalPunctuator(),
            translator: SettingsBackedTextTranslationAPI(),
            rewriter: SettingsBackedTextRewriteAPI(),
            contextProvider: {
                let base = reader.readContext(from: tracker.target)
                // 屏幕上下文: full URL + visible on-screen text are both screen-derived → only
                // attach them when 屏幕上下文 is enabled (508). OFF → no URL, no screen text.
                guard ScreenContextSettings.isEnabled else { return base }
                return base
                    .withBrowserURL(gateReader.readCaptureContext(from: tracker.target).url)
                    .withVisibleScreenText(VisibleTextCollector.collect(from: tracker.target))
            },
            screenContextEnabled: { ScreenContextSettings.isEnabled },
            // 听写翻译 / 划词翻译 = 第一语言（母语）→ 第二语言（外语）, so the shared target is 第二语言.
            translationTargetProvider: { TranslationTargetSettings.secondaryLanguage() },
            // 截图翻译 resolves its own target per captured text (auto 外文→母语) via the 第一/第二语言 pair.
            snapTranslationTargetResolver: { SnapTranslateTargetSettings.resolve(for: $0) },
            rewriteToneProvider: { RewriteStyleSettings.selectedTone() },
            // 写作技能 lane drives heavy 重改写 (改写选中文本 / 表达升级); 听写技能 lane drives the
            // polish hint in `polishStyleHintProvider`. The two lanes are independent (StyleLaneSettings)
            // so changing one never moves the other — the functional split behind 技能平台's two modules.
            rewriteStyleProvider: { RewriteStyleSettings.activeStyle(lane: .writing).heavyRewriteStyle },
            // 462/463 — pack overrides; else App 身份 + 浏览器标签域名 → register; secure field→无 domain(#052); nil→字节一致.
            // P1 — compose the per-app register hint with the learned per-user style descriptor.
            polishStyleHintProvider: {
                let register = RegisterPromptHint.resolve(
                    activePackHint: RewriteStyleSettings.activeStyle(lane: .dictation).polishHint,
                    bundleID: tracker.target?.bundleIdentifier, appName: tracker.target?.localizedName,
                    domain: gateReader.readCaptureContext(from: tracker.target).registerDomain)
                return StyleHintComposer.compose(
                    register: register, personalStyle: StyleProfileSettings.effectiveDescriptor())
            },
            legalRuntime: Self.legalBrainEnabled
                ? (try? LegalSkillRuntime.bundled(
                    executor: RoutingLegalSkillExecutor(),
                    importedStore: FileImportedLegalSkillStore()))
                : nil,
            legalProfileProvider: { try? legalStore?.currentProfile() },
            enabledLegalSkillsProvider: {
                EnabledLegalSkillStore().enabledIDs
            },
            legalGateProvider: { CaptureGatePolicy.adr0014.evaluate(gateReader.readCaptureContext(from: tracker.target)) },
            legalOutputPreferenceProvider: { LegalOutputModePreference(rawValue: UserDefaults.standard.string(forKey: "legal.outputMode") ?? "") ?? .card },
            legalRunRecorder: { run in try? legalStore?.recordRun(run) },
            reverter: { revertable in await reverter.revert(revertable) },
            // 复制弹窗 parity: when the cursor isn't in an editable field, route the dictation result to
            // a copy pill (`.copied`) instead of pasting ⌘V into the void.
            isEditableTarget: { gateReader.hasEditableFocus(in: tracker.target) },
            // 518 follow-up: 设置里的「每次听写都显示纠正入口」——默认关(只在疑似专名听错时提示)。
            correctionChipAlwaysShow: { CorrectionChipSettings.alwaysShow() },
            // 507: end-to-end 听写 latency → labeled with the active ASR engine, emitted to the
            // diagnostics panel (DEBUG) + OSLog totalMs (release).
            latencySink: { trace in Diag.pipeline(trace, engine: ASREngine.selected.rawValue, provider: nil) },
            // 558: 校验成稿（实验）— the BYOK cloud plan compiler behind the 556 verify/render/guard
            // spine. Route policy re-gates on the toggle at compile time (defense in depth: mode
            // routing already gates entry), so a stale in-flight capture can't compile after the
            // user turns the experiment off.
            intentCompiler: SettingsBackedIntentPlanCompiler(),
            intentRoutePolicyProvider: { IntentDictationSettings.isEnabled() ? .injectedCompiler : .unavailable },
            // 562/565: 白名单 grounding —— 词典 = 用户词典 biasing 面(weak-prompt tier)，别名 = 精选
            // 跨形别名表 + 用户确认过的学习别名(learnedAliases,已排除 tombstone)。上下文文本走
            // transformer 内部的屏幕上下文闸，不在这里给。
            intentGroundingProvider: {
                let seed = HotwordAliases.table.flatMap { canonical, surfaces in
                    surfaces.map { IntentGroundingSources.Alias(surface: $0, canonical: canonical) }
                }
                let learned = HotwordLearningHistory(records: AutoLearnHotwordHistorySettings.records())
                    .learnedAliases()
                    .map { IntentGroundingSources.Alias(surface: $0.key, canonical: $0.value) }
                return IntentGroundingSources(
                    dictionaryTerms: ContextHotwordSettings.biasingSets().weakPrompt,
                    aliases: seed + learned)
            },
            // 564: 可选第二阶段润色（默认关）。只作用于已验证 sanitized draft；守卫失败退回原稿。
            intentOptionalPolishEnabledProvider: { IntentDictationSettings.isOptionalPolishEnabled() },
            // 560: bind the verified result to the target it was captured for. Snapshots read the
            // frontmost editable field (ignoring our non-activating panels); the text provider feeds
            // the undo proof; the executor performs the safe delete/restore.
            intentTargetSnapshotProvider: { reader.readInsertionTargetSnapshot(from: tracker.target) },
            intentTargetTextProvider: { reader.readFocusedFieldSnapshot(from: tracker.target)?.text },
            intentUndoExecutor: { await intentReverter.execute($0) },
            // 565: 用户确认 grounded 候选 → 学习 surface→canonical 别名。门(学习开关 + 敏感 App/内容)
            // 走 Core 的 shouldPersist;写入复用既有 词典 + 别名账本(provenance=.manual、undo/tombstone
            // 生效),下次 capture 经上面的 grounding 合并回流。反馈=既有「已加入识别词典」toast。
            intentConfirmedAliasSink: { alias in
                guard IntentConfirmedAliasLearning.shouldPersist(
                    alias,
                    learningEnabled: AutoLearnHotwordSettings.isEnabled,
                    appName: tracker.target?.localizedName ?? tracker.target?.bundleIdentifier) else { return }
                _ = CaptureCorrectionLearner.learn(
                    wrong: alias.surface, correct: alias.canonical, reason: "用户确认候选")
            },
            // 568: 校验成稿 warm-cloud 端到端延迟（stop→visible，逐阶段）→ 进诊断面板(DEBUG) +
            // OSLog totalMs/各阶段 ms + safetyStagesPresent(release)。#568 真机延迟门读这里的数。
            intentLatencySink: { trace in Diag.intentPipeline(trace, route: nil, provider: nil) },
            // 574: content-free failure sub-categories to Release OSLog — five real-Mac blocked
            // cards were undiagnosable because the verify layer logged nothing below transport.
            intentFailureSink: { category in Diag.intentFailure(category) })
        panel = CapsulePanel(vm: vm)
        // 继续对抗/继续完善: a skill result card (反方观点 / 思路推演 / 提示词优化) hands itself to
        // the assistant as the grounded subject; the card played the opening round, so turns
        // start at 加压. Assigned after every stored property is initialized — the closure
        // captures `self`.
        vm.debateSink = { [weak self] subject, script in
            self?.voiceAssistantVM.beginDebate(subject: subject, script: script)
        }
    }

    /// Begin reflecting state in the overlay and listening for the hotkey.
    func start(promptForAccessibility: Bool = true) {
        if promptForAccessibility {
            AccessibilityPermission.promptIfNeeded()
        }
        statusItemController = StatusItemController(controller: self)
        panel.start()
        hotkeyDispatcher.configure()
        hotkeyDispatcher.syncFnMonitor()
        stateOrchestrator.start()

        // LATENCY-MODELLOAD-001: if the saved ASR engine is a local in-process one, prewarm it
        // in the background so the first hotkey after launch isn't blocked by a model load
        // (openless preload_local_asr_in_background). No-op for cloud engines / uninstalled models.
        ASRResidencyPrewarm.onSelection(ASREngine.selected.rawValue)
        PaddleOCRResidencyPrewarm.onSelection(OCREngine.selected.rawValue)
    }

    func trigger() { speechController.trigger() }
    func triggerRaw() { speechController.triggerRaw() }
    func triggerPolished() { speechController.triggerPolished() }
    func triggerExpressInEnglish() { speechController.triggerExpressInEnglish() }
    func triggerRewrite() { speechController.triggerRewrite() }
    func triggerTeaching() { speechController.triggerTeaching() }

    func rewriteSelection(prefetched: String? = nil) {
        selectionController.rewriteSelection(prefetched: prefetched)
    }

    func coachSelection(prefetched: String? = nil) {
        selectionController.coachSelection(prefetched: prefetched)
    }

    func readAloudSelection(prefetched: String? = nil) {
        selectionController.readAloudSelection(prefetched: prefetched)
    }

    func translateSelection(prefetched: String? = nil) {
        selectionController.translateSelection(prefetched: prefetched)
    }

    func snapOCR() {
        guard requireTextModel(feature: "截图翻译") else { return }
        snapOCRController.snapOCR()
    }

    func snapTextOCR() {
        snapOCRController.snapTextOCR()
    }

    /// 截图复制：框选 → 图片本身进剪贴板。无 OCR / 无 LLM，所以不走 requireTextModel。
    func snapImageCopy() {
        snapOCRController.snapImageCopy()
    }

    func addSelectionToDictionary(prefetched: String? = nil) {
        selectionController.addSelectionToDictionary(prefetched: prefetched)
    }

    func askAboutSelection(prefetched: String? = nil) {
        selectionController.askAboutSelection(prefetched: prefetched)
    }

    func confirmInsert() {
        log.info("Confirm insert requested; phase \(String(describing: self.vm.phase), privacy: .public)")
        Task { await vm.confirmInsert() }
    }

    static let insertProbeMarker = CaptureDiagnosticsController.insertProbeMarker
    func probeContext() { diagnosticsController.probeContext() }
    func probeInsert() { diagnosticsController.probeInsert() }
    func probeSelection() { diagnosticsController.probeSelection() }

    #if DEBUG
    func showDesignReviewFixture() { diagnosticsController.showDesignReviewFixture() }
    func showCapsuleListeningFixture() { diagnosticsController.showCapsuleListeningFixture() }
    func showCapsuleFinalizingFixture() { diagnosticsController.showCapsuleFinalizingFixture() }
    func showCapsuleErrorFixture() { diagnosticsController.showCapsuleErrorFixture() }
    func clearDesignFixture() { diagnosticsController.clearDesignFixture() }
    func probeAutoLearnSeed() { diagnosticsController.probeAutoLearnSeed() }
    func showSnapOCRFixture() { SnapOCRFixture.show() }
    #endif

    private static func makeCaptureStore() -> CaptureStore {
        do {
            return ReviewCaptureStore(reviewStore: try SQLiteReviewStore.defaultStore())
        } catch {
            return FileCaptureStore.defaultStore()
        }
    }

}
