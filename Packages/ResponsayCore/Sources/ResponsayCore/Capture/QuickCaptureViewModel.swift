import Foundation
import Observation

@MainActor
@Observable
public final class QuickCaptureViewModel {
    public internal(set) var phase: Phase = .idle
    public var locale: CaptureLocale = .english
    public internal(set) var transcript: String = ""
    public internal(set) var isFinalizingTranscript = false
    /// True while a *cloud* OCR (Snap & Translate) round-trips, so the capsule shows a "识别中…"
    /// spinner instead of dead air. On-device Apple Vision is instant and never sets this.
    public internal(set) var snapRecognizing = false
    public internal(set) var result: ExpressionResult?
    public internal(set) var captureResult: CaptureResult?
    public internal(set) var intentCaptureState: IntentCaptureState?

    /// 559 — the off-screen re-verify context for an Intent-aware needs-review. `internal` so the
    /// macOS view can NEVER reach the plan / source units / raw spans it carries; the capsule only
    /// sees `intentReviewContent`. Cleared on reset/discard.
    var intentReviewProposal: IntentReviewProposal?
    /// 559 — set true when a candidate confirm or draft edit failed re-verification, so the capsule
    /// can say "还没通过校验" while STAYING in review (never a silent unverified insert).
    public internal(set) var intentReviewReverifyRejected = false

    /// 560 — the target the Intent-aware capture was bound to at start (frontmost app / editable
    /// field / selection), re-checked before commit so a verified result never lands in a target
    /// that gained focus while the plan compiled. `internal`; host fills it via Accessibility.
    var intentCaptureStartSnapshot: InsertionTargetSnapshot?
    /// 560 — the short-lifecycle safe-undo evidence for the last Intent-aware insert. Distinct from
    /// `revertableInsertion` (the retired ↩原文 semantics): this only ever deletes the verified text
    /// or restores the replaced selection, never writes the raw transcript back. Cleared on
    /// undo / next capture / window expiry.
    public internal(set) var intentInsertionTransaction: IntentInsertionTransaction?
    /// 560 — observability for the Intent-aware insert's terminal (inserted / reverted / abandoned).
    /// Pure observation, wired into the same `InsertionLifecycle` vocabulary; this ticket does NOT
    /// drive learning off it (#565).
    var intentInsertionLifecycle: InsertionLifecycle?
    // 559 display accessors (`intentReviewContent` / `intentSafeCopyText`) live in +IntentReview.

    /// Text held for the copy pill (`.copied`) — the dictation output that had no editable target to
    /// receive it. The macOS capsule writes it to the clipboard and offers a 📋. Cleared on dismiss/reset.
    public internal(set) var copiedText: String = ""

    public internal(set) var legalCandidates: [LegalCandidateCard] = []
    public internal(set) var legalResponse: LegalSkillResponse?
    public internal(set) var legalResponseRoute: ModelRoute?
    /// 488 找类案：screened online candidates (✅verified / ⚠️AI 生成·未核验) + in-flight flag.
    public internal(set) var legalCaseCandidates: [ScreenedCase] = []
    public internal(set) var isFindingCases = false
    public internal(set) var legalSendConfirm: LegalPrivacyDecision?
    public internal(set) var askSession: SelectionAskSession?

    public internal(set) var selectedAlternative: String?
    public internal(set) var didAutoInsertResult = false

    /// Revert AI (P0b): set right after a direct dictation insert whose AI output differs from the
    /// raw transcript, so the capsule can offer「↩ 原文」. Cleared on revert, on the next capture, or
    /// when the window expires.
    public internal(set) var revertableInsertion: RevertableInsertion?
    /// How long the「↩ 原文」chip stays offered after an insert. Tunable.
    static let revertWindow: UInt64 = 6_000_000_000  // 6s

    /// 518: the text of the last successful direct insert, offered as the capsule's「纠正…」entry.
    /// Unlike revert it fires on raw inserts too (a mishear can sit in a verbatim insert) and does
    /// not need a reverter. Cleared on the next capture, on dismiss, or when the window expires.
    public internal(set) var correctionOffer: String?
    /// 518: non-nil while the correction mini panel edits this text.
    public internal(set) var correctionDraft: String?
    /// How long the「纠正…」chip stays offered after an insert. Tunable.
    static let correctionWindow: UInt64 = 10_000_000_000  // 10s

    public var activeIdiomatic: String { selectedAlternative ?? result?.idiomatic ?? "" }

    /// The review card to show (#3) — derived from the review fields by one tested function, so
    /// `ReviewCardView` switches instead of inferring from an optional cascade, and a review with
    /// no content is an explicit `.empty` rather than a blank coach card. See CONTEXT.md · Result card.
    public var reviewState: CaptureReviewState {
        CaptureReviewState.resolve(
            legalSendConfirm: legalSendConfirm,
            legalResponse: legalResponse,
            legalResponseRoute: legalResponseRoute,
            result: result,
            intentCaptureState: intentCaptureState)
    }

    public func selectAlternative(_ sentence: String) { selectedAlternative = (sentence == result?.idiomatic) ? nil : sentence }
    public func selectIdiomatic() { selectedAlternative = nil }

    public internal(set) var errorMessage: String?
    public internal(set) var level: Float = 0
    public internal(set) var recordingStartedAt: Date?

    let speech: SpeechCaptureService
    let coach: CoachAPI
    let textCoach: CoachAPI
    let store: CaptureStore
    let inserter: GatedTextInserter
    let contextProvider: (@MainActor () -> ExpressionContext?)?
    /// 屏幕上下文 gate (技能偏好). false → no screen-derived context is sent to the cloud
    /// express / 任意提问 paths. nil → enabled. Local routing reads `contextProvider` directly.
    let screenContextEnabled: (@MainActor () -> Bool)?
    /// 375: owns the raw/polish/rewrite/translate/express transform decisions.
    let transformer: CaptureTransformer
    let legal: LegalCaptureCoordinator
    /// 475: secure-input + output-shape signals for the card/上屏 delivery decision.
    let legalGateProvider: (@MainActor () -> CaptureGateDecision)?
    let legalOutputPreferenceProvider: (@MainActor () -> LegalOutputModePreference)?
    /// Revert AI (P0b): macOS-side closure that replaces the inserted `polished` text in the focused
    /// field with `raw` (AX write, keystroke fallback). nil → revert is disabled (e.g. tests/headless).
    let reverter: (@MainActor (RevertableInsertion) async -> Bool)?
    /// macOS-injected: does the capture target currently have an editable focused field? When it
    /// returns `false`, an auto-insert dictation result is offered as a copy pill (`.copied`) instead
    /// of being pasted into a non-editable target, where ⌘V would land nowhere and the text would be
    /// lost. `nil` → always insert (tests/headless keep today's behavior).
    let isEditableTarget: (@MainActor () -> Bool)?
    /// 518 follow-up (user feedback): by default the「纠正…」chip only offers when the inserted
    /// text plausibly contains a mis-heard proper noun (`looksLikeMishearCandidate`). This
    /// setting, when true, bypasses that gate and offers on every successful insert instead —
    /// for a user who wants to manually review/teach every sentence. `nil` → gate stays on
    /// (tests/headless keep the smart-only behavior).
    let correctionChipAlwaysShow: (@MainActor () -> Bool)?
    /// 507: sink for the completed end-to-end dictation latency trace. App-side wires it to
    /// label engine/provider and emit a `pipeline` event + release OSLog. nil → off (tests/headless).
    let latencySink: (@MainActor (LatencyTrace) -> Void)?
    /// 560: reads the current insertion-target identity (bundle / pid / window / editable /
    /// selection) via Accessibility. Sampled at capture start and again before commit so a drifted
    /// target degrades to a safe copy. `nil` → no target-binding gate (tests/headless insert directly).
    let intentTargetSnapshotProvider: (@MainActor () -> InsertionTargetSnapshot?)?
    /// 560: reads the target field's current text at undo time, so undo only fires when the inserted
    /// text is provably still present. `nil` → undo can't verify → it refuses.
    let intentTargetTextProvider: (@MainActor () -> String?)?
    /// 560: executes an `IntentUndoPlan` against the target (delete the verified text / restore the
    /// replaced selection) via AX + keystroke fallback. `nil` → the Intent-aware undo offer is off
    /// (tests/headless; real-host behavior is HITL-verified in #568).
    let intentUndoExecutor: (@MainActor (IntentUndoPlan) async -> Bool)?
    /// 565: sink for a `surface → canonical` alias the user CONFIRMED by picking a grounded entity
    /// candidate. The macOS wiring gates it (learning toggle + sensitive-context privacy gate) and
    /// writes the EXISTING dictionary + learned-alias ledger. `nil` → no confirmed-candidate learning
    /// (tests/headless; the VM only emits, it never persists).
    let intentConfirmedAliasSink: (@MainActor (IntentConfirmedAlias) -> Void)?
    /// 568: sink for the completed Intent-aware warm-cloud latency trace (stop→visible, per stage).
    /// App-side wires it to emit a `pipeline` event + release OSLog (route/provider label + numeric
    /// ms only). Emitted ONLY on a first-pass verified insert; a review-confirm/copy/drift never
    /// counts as a warm sample. `nil` → off (tests/headless).
    let intentLatencySink: (@MainActor (IntentLatencyTrace) -> Void)?
    /// Hand a skill's result card off to a 多轮对抗 session (反方观点 / 思路推演). Injected by the
    /// app layer, which owns the Voice Assistant; `nil` in tests/headless — and since the card
    /// only offers「继续对抗」when this is wired, a context without an assistant shows no button.
    ///
    /// Assigned after construction (unlike the other sinks) because the assistant lives on the
    /// same controller that builds this VM, so it can't capture `self` in the initializer call.
    @ObservationIgnored public var debateSink: (@MainActor (String, DebateScript) -> Void)?
    /// 507: trace for the in-flight dictation — set on the speech path, flushed at insert.
    var latencyTrace: LatencyTrace?
    /// 568: the ASR-final ("stop") boundary of the in-flight Intent-aware capture, captured at the
    /// same instant as the 507 `.transcribe` mark and completed with `.visible` at commit.
    var intentLatencyStopMark: Date?
    var captureGeneration = UUID()
    var activeIntentCompilationID: UUID?
    var pendingLegalCard: LegalCandidateCard?
    /// 07-05 #4: owns the six background `Task` handles (level/partial/failsafe/errorDismiss/
    /// revertExpiry/correctionExpiry) behind `set`/`cancel`/`cancelAll`. `let` (a reference type)
    /// so the handles stay out of `@Observable` tracking. Task bodies stay in this VM.
    let tasks = CaptureTaskSet()

    /// Hard cap on a single listening session. A lost push-to-talk key-up (sleep/wake,
    /// focus loss, AX revoke) can otherwise strand the mic open forever; this stops and
    /// processes whatever was captured instead of recording indefinitely (HOTKEY-STUCK-004).
    static let maxListeningDuration: UInt64 = 180_000_000_000  // 180s
    // 558: the capsule reads this to badge Intent-aware captures (校验成稿中); writes stay internal.
    public internal(set) var activeOutputMode: OutputMode = .coachRewrite

    public init(
        speech: SpeechCaptureService,
        coach: CoachAPI,
        store: CaptureStore,
        inserter: TextInserter,
        textCoach: CoachAPI? = nil,
        polisher: (any TextPolishAPI)? = nil,
        punctuator: (any TextPunctuator)? = nil,
        translator: (any TextTranslationAPI)? = nil,
        rewriter: (any TextRewriteAPI)? = nil,
        contextProvider: (@MainActor () -> ExpressionContext?)? = nil,
        screenContextEnabled: (@MainActor () -> Bool)? = nil,
        translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)? = nil,
        snapTranslationTargetResolver: (@MainActor (String) -> TranslationTargetLanguage)? = nil,
        rewriteToneProvider: (@MainActor () -> RewriteTone)? = nil,
        rewriteStyleProvider: (@MainActor () -> RewriteStyle)? = nil,
        polishStyleHintProvider: (@MainActor () -> String?)? = nil,
        legalRuntime: LegalSkillRuntime? = nil,
        legalProfileProvider: (@MainActor () -> LegalPracticeProfile?)? = nil,
        enabledLegalSkillsProvider: (@MainActor () -> Set<String>?)? = nil,
        legalGateProvider: (@MainActor () -> CaptureGateDecision)? = nil,
        legalOutputPreferenceProvider: (@MainActor () -> LegalOutputModePreference)? = nil,
        legalRunRecorder: (@MainActor (LegalSkillRun) -> Void)? = nil,
        reverter: (@MainActor (RevertableInsertion) async -> Bool)? = nil,
        isEditableTarget: (@MainActor () -> Bool)? = nil,
        correctionChipAlwaysShow: (@MainActor () -> Bool)? = nil,
        latencySink: (@MainActor (LatencyTrace) -> Void)? = nil,
        intentCompiler: (any IntentPlanCompiler)? = nil,
        intentRoutePolicyProvider: (@MainActor () -> IntentRoutePolicy)? = nil,
        intentGroundingProvider: (@MainActor () -> IntentGroundingSources)? = nil,
        intentOptionalPolishEnabledProvider: (@MainActor () -> Bool)? = nil,
        intentTargetSnapshotProvider: (@MainActor () -> InsertionTargetSnapshot?)? = nil,
        intentTargetTextProvider: (@MainActor () -> String?)? = nil,
        intentUndoExecutor: (@MainActor (IntentUndoPlan) async -> Bool)? = nil,
        intentConfirmedAliasSink: (@MainActor (IntentConfirmedAlias) -> Void)? = nil,
        intentLatencySink: (@MainActor (IntentLatencyTrace) -> Void)? = nil,
        intentFailureSink: (@Sendable (String) -> Void)? = nil
    ) {
        self.speech = speech
        self.coach = coach
        self.textCoach = textCoach ?? coach
        self.store = store
        self.inserter = GatedTextInserter(inserter)
        self.contextProvider = contextProvider
        self.screenContextEnabled = screenContextEnabled
        self.legalGateProvider = legalGateProvider
        self.legalOutputPreferenceProvider = legalOutputPreferenceProvider
        self.reverter = reverter
        self.isEditableTarget = isEditableTarget
        self.correctionChipAlwaysShow = correctionChipAlwaysShow
        self.latencySink = latencySink
        self.intentTargetSnapshotProvider = intentTargetSnapshotProvider
        self.intentTargetTextProvider = intentTargetTextProvider
        self.intentUndoExecutor = intentUndoExecutor
        self.intentConfirmedAliasSink = intentConfirmedAliasSink
        self.intentLatencySink = intentLatencySink
        self.transformer = CaptureTransformer(
            polisher: polisher,
            rewriter: rewriter,
            translator: translator,
            contextProvider: contextProvider,
            screenContextEnabled: screenContextEnabled,
            translationTargetProvider: translationTargetProvider,
            snapTranslationTargetResolver: snapTranslationTargetResolver,
            rewriteToneProvider: rewriteToneProvider,
            rewriteStyleProvider: rewriteStyleProvider,
            polishStyleHintProvider: polishStyleHintProvider,
            punctuator: punctuator,
            intentCompiler: intentCompiler,
            intentRoutePolicyProvider: intentRoutePolicyProvider,
            intentGroundingProvider: intentGroundingProvider,
            intentOptionalPolishEnabledProvider: intentOptionalPolishEnabledProvider,
            intentFailureSink: intentFailureSink)
        self.legal = LegalCaptureCoordinator(
            runtime: legalRuntime,
            contextProvider: contextProvider,
            profileProvider: legalProfileProvider,
            enabledProvider: enabledLegalSkillsProvider,
            gateProvider: legalGateProvider,
            runRecorder: legalRunRecorder)
    }

    public func toggle(outputMode: OutputMode = .coachRewrite) async {
        switch phase {
        case .listening: await stopAndProcess(outputMode: activeOutputMode)
        case .thinking:  return
        case .idle, .review, .error, .copied: startListening(outputMode: outputMode)
        }
    }

    /// Dismiss the copy pill (`.copied`) — the 📋 button and the 5s auto-dismiss both call this.
    public func dismissCopied() {
        guard phase == .copied else { return }
        copiedText = ""
        correctionOffer = nil   // the copy card already offered 纠正; don't leave a stale idle chip
        phase = .idle
    }

    public func push(outputMode: OutputMode = .coachRewrite) {
        if phase != .listening { startListening(outputMode: outputMode) }
    }

    public func release() async {
        if phase == .listening { await stopAndProcess(outputMode: activeOutputMode) }
    }

    public func confirmInsert() async {
        guard phase == .review, result != nil else { return }
        phase = .idle
        do {
            try await inserter.insert(activeIdiomatic)
        } catch {
            enterError(error.localizedDescription)
        }
    }

    public func discard() {
        guard phase == .review else { return }; reset(); phase = .idle
    }

    // MARK: - Revert AI (P0b)

    /// After a spoken-dictation transform, offer「↩ 原文」iff the AI actually changed the text:
    /// a direct auto-insert (`.insertImmediately`) whose `insertText` differs from the spoken
    /// transcript. Raw-mode (text unchanged) and selection-replace (`.replaceSelection`) never offer it.
    func offerRevertIfNeeded() {
        // A copy-pill result was never inserted, so there is nothing to revert.
        guard phase != .copied,
              reverter != nil,
              let capture = captureResult,
              capture.insertPolicy == .insertImmediately,
              let inserted = capture.insertText,
              !inserted.isEmpty,
              inserted != capture.sourceTranscript,
              !capture.sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        revertableInsertion = RevertableInsertion(polished: inserted, raw: capture.sourceTranscript)
        tasks.set(.revertExpiry, Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.revertWindow)
            guard !Task.isCancelled, let self else { return }
            self.revertableInsertion = nil
        })
    }

    /// Swap the just-inserted AI text back to the raw transcript in the focused field. Optimistically
    /// clears the offer so the chip dismisses immediately; the macOS reverter does the actual replace.
    public func revertLastInsertion() async {
        guard let revertable = revertableInsertion, let reverter else { return }
        tasks.cancel(.revertExpiry)
        revertableInsertion = nil
        _ = await reverter(revertable)
    }

    // MARK: - 纠正并学习 (518)

    /// Offer the「纠正…」entry after any successful direct insert — raw or transformed. The offer
    /// carries the inserted text so the mini panel can show it and let the user pick the mishear.
    /// True when `text` warrants a 纠正 entry: the「每次听写都显示」setting is on, or the text is
    /// shaped like it holds a mis-heard proper noun. Shared by the insert path and the copy-pill
    /// path so both surfaces gate 纠正 identically.
    func shouldOfferCorrection(for text: String) -> Bool {
        (correctionChipAlwaysShow?() ?? false) || Self.looksLikeMishearCandidate(text)
    }

    func offerCorrectionIfNeeded() {
        // `phase == .idle` scopes this to the *insert* path: a no-editable-target result routes to
        // `.copied` (which sets its own offer via `shouldOfferCorrection` in `apply`) and returns
        // before inserting, so here we only handle text that actually landed in an app.
        guard phase == .idle,
              let capture = captureResult,
              capture.insertPolicy == .insertImmediately,
              let inserted = capture.insertText,
              !inserted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              shouldOfferCorrection(for: inserted)
        else { return }
        correctionOffer = inserted
        tasks.set(.correctionExpiry, Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.correctionWindow)
            guard !Task.isCancelled, let self, self.correctionDraft == nil else { return }
            self.correctionOffer = nil
        })
    }

    /// Open the correction mini panel on the offered text; cancels the expiry so the offer can't
    /// vanish mid-typing. No-op when nothing is offered.
    public func beginCorrection() {
        guard let offer = correctionOffer else { return }
        tasks.cancel(.correctionExpiry)
        // From the copy pill (`.copied`): leave it so the keyable correction panel can take over
        // (it only renders while phase == .idle). The text was already auto-copied — nothing lost.
        if phase == .copied { copiedText = ""; phase = .idle }
        correctionDraft = offer
    }

    /// Close the correction panel and retire the offer (confirm and cancel both end here).
    public func dismissCorrection() {
        tasks.cancel(.correctionExpiry)
        correctionDraft = nil
        correctionOffer = nil
    }

    /// 518 follow-up (user feedback 2026-07-03: showing the chip on every dictation was too noisy)
    /// — true when `text` holds at least one mis-heard-shaped ASCII token (proper noun / brand /
    /// code term). Plain Chinese prose with no such token returns false, so the chip stays quiet on
    /// the common case. The shape rule lives in `MishearCandidates` (shared with the chip's label),
    /// so the show/hide gate and the「点名可疑词」title can never disagree.
    static func looksLikeMishearCandidate(_ text: String) -> Bool {
        !MishearCandidates.tokens(in: text).isEmpty
    }

    /// Abort an in-flight capture without inserting (STATE-CANCEL-002). Ordinary modes retain
    /// the listening-only rule; Intent-aware may also cancel while finalizing/compiling, where its
    /// generation gates discard any late completion. Also used on app quit and sleep/wake.
    public func cancelCapture() async {
        if phase == .thinking,
           activeOutputMode == .intentAwareDictation,
           isFinalizingTranscript || activeIntentCompilationID != nil {
            reset()
            phase = .idle
            return
        }
        guard phase == .listening else { return }
        tasks.cancel(.level); level = 0
        tasks.cancel(.partial)
        tasks.cancel(.failsafe)
        _ = try? await speech.stop()
        reset()
        phase = .idle
    }

    public func fail(_ message: String) {
        guard phase != .listening else { return }
        // Admit the recognizing-`.thinking` case so an empty/failed cloud OCR exits the spinner.
        guard phase != .thinking || snapRecognizing else { return }
        reset(); enterError(message)
    }

    /// Show the capsule's "识别中…" spinner while a cloud OCR round-trips (the snap controller calls
    /// this once the screenshot is captured, before the network call). `processText` (recognized) /
    /// `fail` (empty·failed) / `endSnapRecognizing` (cancelled·Snap & Copy) each transition out of it.
    public func beginSnapRecognizing() {
        guard phase == .idle || phase == .review || phase == .error else { return }
        reset()
        snapRecognizing = true
        phase = .thinking
    }

    /// Leave the recognizing spinner with no capsule result (capture cancelled, or Snap & Copy done).
    public func endSnapRecognizing() {
        guard snapRecognizing else { return }
        reset()
        phase = .idle
    }
    // DEBUG preview/screenshot fixtures live in +DebugFixtures.
}
