import AppKit
import OSLog
import ResponsayCore

@MainActor
final class CaptureSelectionController {
    private let vm: QuickCaptureViewModel
    private let targetTracker: TargetAppTracker
    private let selectionReader: SelectionTextReader
    private let log: Logger
    private let legalBrainEnabled: () -> Bool
    private let accessibilityPrompt: @MainActor () -> Bool
    private let textModelPreflight: @MainActor (QuickCaptureViewModel.OutputMode) -> Bool
    /// 划词翻译 routing: true when the target's focused field is editable (→ translate-and-replace),
    /// false for read-only contexts (→ translation preview card). Defaults to read-only-safe.
    private let isTargetEditable: @MainActor () -> Bool
    /// 任意提问: hand the captured selection to the open-chat assistant (Global Voice Assistant),
    /// seeding it with the selection before the next voice question.
    private let onSelectionAsk: @MainActor (String) -> Void
    /// 反方观点多轮对抗: hand the selected argument to the Voice Assistant in 对抗 mode
    /// (审稿人加压 → 作者回应, advanced by the 任意提问 hotkey).
    private let onCounterargumentDebate: @MainActor (String) -> Void
    private lazy var selectionActionPanel = SelectionActionPanel()
    private lazy var verifyMenuController = SelectionVerifyMenuController()
    private let readAloudController = ReadAloudController()
    /// 屏底浮窗朗读控制条(暂停/继续 + 停止)。lazy 确保 `start()` 只挂一次观察。
    private lazy var readAloudControlPanel: ReadAloudControlPanel = {
        let panel = ReadAloudControlPanel(controller: readAloudController)
        panel.start()
        return panel
    }()
    private let legalSkillLibrary = LegalSkillLibrary()

    init(
        vm: QuickCaptureViewModel,
        targetTracker: TargetAppTracker,
        selectionReader: SelectionTextReader,
        log: Logger,
        legalBrainEnabled: @escaping () -> Bool,
        accessibilityPrompt: @escaping @MainActor () -> Bool = { AccessibilityPermission.promptIfNeeded() },
        textModelPreflight: @escaping @MainActor (QuickCaptureViewModel.OutputMode) -> Bool = { _ in true },
        isTargetEditable: @escaping @MainActor () -> Bool = { false },
        onSelectionAsk: @escaping @MainActor (String) -> Void = { _ in },
        onCounterargumentDebate: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.vm = vm
        self.targetTracker = targetTracker
        self.selectionReader = selectionReader
        self.log = log
        self.legalBrainEnabled = legalBrainEnabled
        self.accessibilityPrompt = accessibilityPrompt
        self.textModelPreflight = textModelPreflight
        self.isTargetEditable = isTargetEditable
        self.onSelectionAsk = onSelectionAsk
        self.onCounterargumentDebate = onCounterargumentDebate
    }

    func rewriteSelection(prefetched: String? = nil) {
        processSelection(outputMode: .rewriteSameLanguage, actionName: "Heavy rewrite selection", prefetched: prefetched)
    }

    func showSelectionPopup(text: String) {
        let classification = SelectionClassifier().classify(text)
        // 划词菜单 actions are content-dependent (SelectionActionResolver), then gated by 技能平台
        // 激活 (SelectionMenuGate): only 翻译/朗读/加入词典/任意提问 are fixed — 引注源验/来源辅助检索/
        // 规范排版 appear only when their backing skill / SelectionTool is on. The saved
        // SelectionMenuLayout then decides
        // the final order + show/hide.
        let contentActions = SelectionActionResolver().actions(classification: classification)
        let actions = SelectionMenuGate().available(from: contentActions)
        let skills = enabledPracticeSkills()
        let items = SelectionMenuLayoutStore.load().resolve(
            availableActions: actions,
            availableSkills: skills.map { (id: $0.id, title: $0.title) })

        selectionActionPanel.show(
            at: NSEvent.mouseLocation, text: text,
            items: items,
            onPick: { [weak self] action, pickedText in
                self?.executeSelectionAction(action, selectedText: pickedText)
            },
            onPickSkill: { [weak self] skillId, pickedText in
                self?.runPracticeSkill(skillId: skillId, selectedText: pickedText)
            },
            onCustomize: { [weak self] in self?.openMenuCustomizer() })
    }

    /// The enabled generation skills flattened into the 划词菜单 — the same subset
    /// `LegalSkillsScreen` files under 划词生成 (legal category, minus the verification /
    /// retrieval skills which have their own explicit 来源核验 / 来源辅助检索 entries),
    /// filtered to what the user has enabled. Loaded per-show (cheap, user-initiated).
    private func enabledPracticeSkills() -> [SelectionPracticeSkill] {
        legalSkillLibrary.enabledPracticeSkills()
            .map { SelectionPracticeSkill(id: $0.id, title: $0.metadata.title) }
    }

    func coachSelection(prefetched: String? = nil) {
        processSelection(outputMode: .idiomaticPreview, actionName: "Preview idiomatic selection", prefetched: prefetched)
    }

    /// 规范排版: 确定性整理中文标点 / 全半角 / 空格 + AI 拼断行 → 就地替换选区（同翻译替换那条 replaceSelection 路径）。
    func normalizeTypographySelection(prefetched: String? = nil) {
        processSelection(outputMode: .normalizeTypographySelection, actionName: "Normalize typography on selection", prefetched: prefetched)
    }

    func readAloudSelection(prefetched: String? = nil) {
        guard prepareSelectionAction("Read Aloud selection", applyLocale: false) else { return }
        _ = readAloudControlPanel   // ensure the bottom-center 暂停/停止 control is live
        Task {
            if let selectedText = await resolveSelectionText(prefetched: prefetched),
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                readAloudController.toggleRead(.followReadSeed(from: selectedText))
            }
        }
    }


    func translateSelection(prefetched: String? = nil) {
        // Editable target (Notes, input box) → translate-and-replace; read-only (reading a PDF /
        // web page / WeChat message) → show the translation in a preview card instead of trying to
        // overwrite text that can't be written (which silently no-ops).
        let mode: QuickCaptureViewModel.OutputMode = isTargetEditable() ? .translateWritten : .translatePreview
        processSelection(outputMode: mode, actionName: "Translate selection", prefetched: prefetched)
    }

    func addSelectionToDictionary(prefetched: String? = nil) {
        guard prepareSelectionAction("Add selection to recognition dictionary", applyLocale: false) else { return }
        Task {
            let term = await resolveSelectionText(prefetched: prefetched) ?? ""
            if ContextHotwordSettings.addManual(term) {
                log.info("Added selection to recognition dictionary (\(term.count, privacy: .public) chars)")
            } else {
                MainWindowController.shared.show()
            }
        }
    }

    func askAboutSelection(prefetched: String? = nil) {
        let actionName = "Ask about selection"
        guard prepareSelectionAction(actionName) else { return }
        Task {
            if let selectedText = await resolveSelectionText(prefetched: prefetched),
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log.info("Selected text captured for ask; length \(selectedText.count, privacy: .public)")
                onSelectionAsk(selectedText)
            } else {
                log.error("\(actionName, privacy: .public) failed: no text selected")
                vm.fail("没有读到选中文本。请先在目标 App 里选中一段文字。")
            }
        }
    }

    /// fn+V 划词菜单: read the current selection (AX → ⌘C fallback) on demand, then pop the
    /// cursor-side action menu (来源核验 / 翻译 / 朗读 / 加入识别词典 …). The keyboard counterpart of
    /// the old hold-and-drag popup — same menu, summoned explicitly instead of on every drag-select.
    func showSelectionMenuFromHotkey() {
        guard prepareSelectionAction("Selection menu", applyLocale: false) else { return }
        Task {
            guard let text = await resolveSelectionText(prefetched: nil),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.error("Selection menu failed: no text selected")
                vm.fail("没有读到选中文本。请先在目标 App 里选中一段文字。")
                return
            }
            // ponytail: menu pops at NSEvent.mouseLocation (matches the old drag popup); anchoring to
            // the selection's AX bounds (kAXBoundsForRange) is a later polish if it reads disconnected.
            showSelectionPopup(text: text)
        }
    }

    func executeSelectionAction(_ action: SelectionAction, selectedText: String? = nil) {
        switch action {
        case .translate:
            translateSelection(prefetched: selectedText)
        case .normalizeTypography:
            normalizeTypographySelection(prefetched: selectedText)
        case .readAloud:
            readAloudSelection(prefetched: selectedText)
        case .verify:
            openVerificationForSelection(selectedText)
        case .assistedSearch:
            runLegalSkillSelection(skillId: "research.search_strategy.cn", prefetched: selectedText,
                                   actionName: "Assisted search on selection")
        case .addToDictionary:
            addSelectionToDictionary(prefetched: selectedText)
        case .ask:
            askAboutSelection(prefetched: selectedText)
        }
    }

    /// 实务辅助 ▾ pick — run one named practice/academic skill directly on the selection.
    /// Each skill declares its own 互动形态 (`interaction`): `.conversation` skills open a
    /// multi-turn 对抗/对话 in the Voice Assistant; `.oneShot` skills produce a result card.
    /// No bundled skill declares `.conversation` today — 反方观点 produces its card first and
    /// enters the 对抗 from the result panel — so this branch serves imported skills.
    func runPracticeSkill(skillId: String, selectedText: String? = nil) {
        switch legalSkillLibrary.interaction(forSkillId: skillId) {
        case .conversation:
            // Every conversation skill today is adversarial, so this reuses the 反方观点 entry
            // (round-based 对抗 via CounterargumentStance). When a non-adversarial conversation
            // skill appears, split a generic conversation persona from CounterargumentStance.
            startCounterargumentDebate(prefetched: selectedText)
        case .oneShot:
            runLegalSkillSelection(skillId: skillId, prefetched: selectedText,
                                   actionName: "Run 实务辅助 skill on selection")
        }
    }

    /// Hand the selected argument to the Voice Assistant in 多轮对抗 mode. Same gating as a
    /// legal skill run (`legalBrainEnabled` build flag + text-model preflight); the argument
    /// becomes the grounded selection and turns are driven by the 任意提问 hotkey.
    private func startCounterargumentDebate(prefetched: String?) {
        guard legalBrainEnabled() else {
            log.debug("反方观点对抗 ignored: LegalBrainEnabled is off")
            return
        }
        guard textModelPreflight(.askSelection) else { return }
        guard prepareSelectionAction("Counterargument debate on selection") else { return }
        Task {
            guard let text = await resolveSelectionText(prefetched: prefetched),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.error("反方观点对抗 failed: no text selected")
                vm.fail("没有读到选中文本。请先在目标 App 里选中要推敲的论点。")
                return
            }
            onCounterargumentDebate(text)
        }
    }

    /// 自定义菜单… — open 设置 › 划词菜单, where the user reorders / shows / hides the menu's rows
    /// (and from there can jump to the 技能库 to enable more skills).
    func openMenuCustomizer() {
        MacSettingsWindowController.shared.show(section: .selectionMenu)
    }

    /// Shared body for 来源辅助检索 / 实务辅助: run one named legal skill on the captured
    /// selection through the VM's privacy-gated direct-run path. Gated by the `legalBrainEnabled`
    /// build flag; the LLM-configured check is enforced inside `vm.runLegalSkillOnSelection`
    /// (`法律技能未配置`), so no separate text-model preflight is needed here.
    private func runLegalSkillSelection(skillId: String, prefetched: String?, actionName: String) {
        guard legalBrainEnabled() else {
            log.debug("\(actionName, privacy: .public) ignored: LegalBrainEnabled is off")
            return
        }
        guard prepareSelectionAction(actionName) else { return }
        Task {
            guard let text = await resolveSelectionText(prefetched: prefetched),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.error("\(actionName, privacy: .public) failed: no text selected")
                vm.fail("没有读到选中文本。请先在目标 App 里选中一段文字。")
                return
            }
            await vm.runLegalSkillOnSelection(skillId: skillId, text: text)
        }
    }

    private func resolveSelectionText(prefetched: String?) async -> String? {
        if let prefetched, !prefetched.isEmpty { return prefetched }
        return await selectionReader.readSelectedText(from: targetTracker.target)
    }

    /// 点「来源核验」→ 弹分组源菜单（法规/案例/文献/兜底），用户挑一个源去核验。
    /// 抽到法条/案号/文献坐标就用坐标当检索词，否则用整段选区；付费/JS 站由路由层
    /// 自动走必应 site: 落到结果页。一次开一个，不再自动开 4 个。
    /// 引注源验: selection → run the fact-check skill → result card (法条/案例/文献 锚点 +
    /// 自动联网核验 + 命中跳库 / 未命中标待核). When `legalBrainEnabled` is off (no LLM skill run), fall back to
    /// the deterministic source menu so offline / no-key users still get a manual 挑库 jump.
    private func openVerificationForSelection(_ text: String?) {
        if legalBrainEnabled() {
            runLegalSkillSelection(skillId: "verification.fact_check.cn",
                                   prefetched: text, actionName: "引注源验 on selection")
        } else {
            openVerifyMenuFallback(text)
        }
    }

    /// Deterministic source-menu fallback (the pre-引注源验 behavior): extract 法条/案号 anchors,
    /// pop the grouped source menu, jump to the picked database in the browser.
    private func openVerifyMenuFallback(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        guard prepareSelectionAction("Verify selection", applyLocale: false) else { return }
        let anchors = FactCoordinateExtractor().extract(from: text)
        let groups = SelectionVerifyMenu().build(selectedText: text, anchors: anchors)
        guard !groups.isEmpty else { return }
        log.info("selection verify menu: \(anchors.count, privacy: .public) anchors, \(groups.count, privacy: .public) groups")
        verifyMenuController.present(groups: groups, at: NSEvent.mouseLocation) { [weak self] item in
            self?.openVerifyRoute(item.route)
        }
    }

    private func openVerifyRoute(_ route: VerificationRoute) {
        guard let url = route.url else { return }
        NSWorkspace.shared.open(url)
        // Clipboard hygiene: only pre-load the query for manual paste when the opened
        // source carries no query in its URL (a bare front-end search page); direct +
        // Bing site: routes already carry it, so the user's clipboard is left untouched.
        let pasteQuery = SelectionVerifyClipboard.pasteQuery(openedRoutes: [route])
        if let pasteQuery {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pasteQuery, forType: .string)
            // The page can't be pre-filled (no URL params), so tell the user the 检索式 is on the
            // clipboard — otherwise an opened-but-empty form reads as "broken". 知网 lands on 高级检索
            // but the expression is 专业检索 syntax, so point there explicitly.
            SelectionHintToast.shared.show(route.source == .cnki
                ? "知网检索式已复制，切到「专业检索」粘贴即可"
                : "检索式已复制，粘贴到该站检索框即可")
        }
        log.info("selection verify open: \(route.source.rawValue, privacy: .public), clipboard \(pasteQuery == nil ? "kept" : "set", privacy: .public)")
    }

    private func processSelection(outputMode: QuickCaptureViewModel.OutputMode, actionName: String, prefetched: String? = nil) {
        guard textModelPreflight(outputMode) else { return }
        guard prepareSelectionAction(actionName) else { return }
        Task {
            if let selectedText = await resolveSelectionText(prefetched: prefetched) {
                log.info("Selected text captured; length \(selectedText.count, privacy: .public)")
                await vm.processText(selectedText, outputMode: outputMode)
            } else {
                log.error("\(actionName, privacy: .public) failed: no text selected")
                vm.fail("没有读到选中文本。请先在目标 App 里选中一段文字。")
            }
        }
    }

    @discardableResult
    private func prepareSelectionAction(_ actionName: String, applyLocale: Bool = true) -> Bool {
        guard vm.phase != .listening, vm.phase != .thinking else { return false }
        log.info("\(actionName, privacy: .public) requested")
        guard accessibilityPrompt() else {
            log.error("\(actionName, privacy: .public) blocked: Accessibility permission is not trusted")
            vm.fail(AccessibilityPermission.guidance)
            return false
        }
        targetTracker.capture()
        if applyLocale {
            applyLocalePreference()
        }
        return true
    }


    private func applyLocalePreference() {
        if let raw = UserDefaults.standard.string(forKey: "defaultLocale"),
           let locale = CaptureLocale(rawValue: raw) {
            vm.locale = locale
        }
    }
}
