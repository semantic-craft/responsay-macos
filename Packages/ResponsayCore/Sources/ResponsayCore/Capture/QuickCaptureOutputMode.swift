import Foundation

extension QuickCaptureViewModel {
    public enum Phase: Sendable, Equatable { case idle, listening, thinking, review, error, copied }

    public enum OutputMode: Sendable, Equatable {
        case rawTranscript
        case polishedTranscript
        /// 校验成稿: same-language, final-only structured intent compilation.
        /// No production trigger or setting is exposed by issue 556.
        case intentAwareDictation
        /// 重改写 (Heavy rewrite): same-language restructure via `/rewrite`, steered by a
        /// `RewriteTone`. Selection-driven (改写选中文本).
        case rewriteSameLanguage
        /// 规范排版 (Normative typesetting): 确定性规则整理中文标点 / 全半角 / 空格 + AI 只拼断行，
        /// 就地替换选区，内容一字不改（指纹护栏）。移植自法墨输入法（2026-07-22）。
        case normalizeTypographySelection
        /// 地道表达: selection-only idiomatic paraphrase preview. No teaching, no silent insert.
        case idiomaticPreview
        case coachRewrite
        /// 听写翻译 (spoken): translate the *intent* of just-spoken words the most natural way
        /// in the target language. The Fn+Shift speech action.
        case translateSpoken
        /// 划词翻译 (editable target): faithful translation of selected text, inserted in place.
        /// Auto-direction via the 第一/第二语言 pair (外文→第一; 第一→第二), like 截图翻译.
        case translateWritten
        /// 划词翻译 read-only preview (non-editable target): translate card only, never inserts.
        /// Same auto-direction (第一/第二语言 pair) target as `.translateWritten` — read-only 外文 → 母语.
        case translatePreview
        case teachingFeedback
        /// Dormant (legacy card-based 任意提问): selection-as-context + voice question,
        /// answered inline. Superseded by routing into the Global Voice Assistant;
        /// kept for the future legal-skill entry. See SelectionAskEnvelope.
        case askSelection
    }
}

/// Every per-mode fact in one place. An exhaustive `switch` over the mode (no `default`)
/// means the compiler forces any new mode to declare its facts here — instead of being
/// re-derived by switches scattered across the capture pipeline.
public struct OutputModeSpec: Sendable, Equatable {
    /// Which ASR profile this mode dictates (Coach/selection stay 忠实档; only Dictate polishes).
    public let asrProfile: SpeechCaptureProfile
    /// Whether the mode needs a text-rewrite model configured before it can run.
    public let requiresTextModel: Bool
    /// Translate fidelity, fixed per mode — `nil` for non-translate modes. Replaces the old
    /// input-keyed guess that let `.translate` mean two things.
    public let translateStyle: TextTranslationStyle?

    public init(
        asrProfile: SpeechCaptureProfile,
        requiresTextModel: Bool,
        translateStyle: TextTranslationStyle? = nil
    ) {
        self.asrProfile = asrProfile
        self.requiresTextModel = requiresTextModel
        self.translateStyle = translateStyle
    }
}

extension QuickCaptureViewModel.OutputMode {
    public var spec: OutputModeSpec {
        switch self {
        case .rawTranscript:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: false)
        case .polishedTranscript:
            OutputModeSpec(asrProfile: .dictation, requiresTextModel: false)
        case .intentAwareDictation:
            // Preserve correction/control cues for the compiler. Capability routing is owned by
            // the dedicated intent route, not the ordinary TextPolish model preflight.
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: false)
        case .rewriteSameLanguage:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        case .normalizeTypographySelection:
            // 段落重排（reflow）需要 LLM；确定性规则整理本身不需要，但整技能以有文字模型为前提（preflight 门槛）。
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        case .idiomaticPreview:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        case .coachRewrite:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        case .translateSpoken:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true, translateStyle: .nativeIntent)
        case .translateWritten:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true, translateStyle: .literal)
        case .translatePreview:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true, translateStyle: .literal)
        case .teachingFeedback:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        case .askSelection:
            OutputModeSpec(asrProfile: .faithful, requiresTextModel: true)
        }
    }
}
