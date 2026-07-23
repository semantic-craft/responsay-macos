import Foundation

#if DEBUG
// DEBUG-only fixtures that stage the capsule into a given state for real-Mac screenshot / VoiceOver
// review (the GUI accessory app can't run headless). Not compiled into release.
extension QuickCaptureViewModel {
    public func loadDesignReviewFixture() {
        reset(); transcript = "This conclusion feels not very stable."
        result = ExpressionResult(
            idiomatic: "I'm not sure that conclusion holds up.",
            original: transcript,
            reasons: [
                "“holds up” 更像英语里评价论证是否站得住的说法。",
                "“I'm not sure” 比直接否定更自然，适合学术讨论里的保留态度。"
            ],
            thinkingShift: "中文里常说“感觉不稳”；英语学术讨论更常把判断落到论证是否经得起检验。",
            alternatives: [
                "I don't think that conclusion is fully supported.",
                "That conclusion may need stronger evidence."
            ])
        phase = .review
    }

    public func loadCapsuleListeningFixture() {
        reset(); transcript = "今天我们测试 Qwen3-ASR 和 CLSCI"; level = 0.62
        recordingStartedAt = Date().addingTimeInterval(-8); phase = .listening
    }

    public func loadCapsuleFinalizingFixture() {
        reset(); transcript = "今天我们测试 Qwen3-ASR 和 CLSCI"; isFinalizingTranscript = true; phase = .thinking
    }

    public func loadCapsuleErrorFixture() { fail("当前是密码 / 安全输入框,已禁用语音输入。") }
    public func clearDesignFixture() { reset(); phase = .idle }

    /// 559 — the needs-review card with two grounded candidates + an editable draft, for real-Mac
    /// screenshot review of the capsule. Mirrors the injected fixture the Core tests use.
    public func loadIntentReviewFixture() {
        reset()
        let transcriptText = "周三，不对，周四"
        transcript = transcriptText
        activeOutputMode = .intentAwareDictation
        let units = IntentSourceSegmenter.segment(transcriptText)
        let correctionPlan = IntentPlan(
            version: 1, decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .correction),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [.init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))])
        let keepBothPlan = IntentPlan(
            version: 1, decision: .render,
            units: units.map { .init(source: .init($0), role: .content) }, supersessions: [])
        presentIntentReview(IntentReviewProposal(
            transcript: transcriptText, sourceUnits: units, sanitizedDraft: "周四",
            candidates: [
                .init(id: "c-correction", value: "只保留「周四」", evidence: "改口", plan: correctionPlan),
                .init(id: "c-keepboth", value: "两者都写", evidence: "并列", plan: keepBothPlan)
            ],
            forbiddenFragments: ["不对", "周三"]))
    }

    /// 559 — the safe-unavailable card for a chosen reason (screenshot review of the 6-way copy).
    public func loadIntentSafeUnavailableFixture(_ reason: IntentUnavailableReason = .invalidPlan) {
        reset()
        transcript = "周三，不对，周四"
        activeOutputMode = .intentAwareDictation
        intentCaptureState = .safeUnavailable(reason)
        phase = .review
    }
}
#endif
