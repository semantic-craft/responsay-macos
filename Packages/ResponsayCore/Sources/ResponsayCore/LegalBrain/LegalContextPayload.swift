import Foundation

// MARK: - Model routing, context payload, router output
//
// The confidentiality boundary (issue 110, ADR-0014) and the platform-agnostic input to
// skill execution. Default scope sends only selected text + scene tag; surrounding text is
// used for local routing only. `source` distinguishes AX vs OCR per ADR-0021.

/// Where a model call is allowed to run for this request.
public enum ModelRoute: String, Codable, Sendable {
    case localOnly
    case cloudAllowed
    case cloudRequiresUserConfirm
    case blocked
}

/// How much of the surrounding context may be sent.
public enum ContextScope: String, Codable, Sendable {
    case selectedTextOnly
    case selectedTextPlusLocalHeading
    case selectedTextPlusSurroundingText
}

/// How the context text was obtained. OCR is explicit/user-invoked only (ADR-0021).
public enum LegalContextSource: String, Codable, Sendable {
    case accessibility
    case ocr
}

/// The platform-agnostic payload a skill execution receives. Built from `ExpressionContext`
/// after the privacy policy (issue 110) decides scope/route. `windowTitleHash` defaults to a
/// hash so the raw window title is not sent unless allowed.
public struct LegalContextPayload: Codable, Sendable {
    public let selectedText: String
    public let nearbyHeading: String?
    public let scene: LegalScene
    public let stage: LegalStage
    public let appName: String
    public let windowTitleHash: String?
    public let hotwords: [String]
    public let contextScope: ContextScope
    public let source: LegalContextSource

    public init(
        selectedText: String,
        nearbyHeading: String? = nil,
        scene: LegalScene,
        stage: LegalStage,
        appName: String,
        windowTitleHash: String? = nil,
        hotwords: [String] = [],
        contextScope: ContextScope = .selectedTextOnly,
        source: LegalContextSource = .accessibility
    ) {
        self.selectedText = selectedText
        self.nearbyHeading = nearbyHeading
        self.scene = scene
        self.stage = stage
        self.appName = appName
        self.windowTitleHash = windowTitleHash
        self.hotwords = hotwords
        self.contextScope = contextScope
        self.source = source
    }
}

/// Output of the scene/stage router (issue 104). Rules-first; low confidence → ask user.
public struct SceneStageClassification: Codable, Sendable {
    public let scene: LegalScene
    public let stage: LegalStage
    public let confidence: Double
    public let reasons: [String]
    public let shouldAskUser: Bool

    public init(
        scene: LegalScene,
        stage: LegalStage,
        confidence: Double,
        reasons: [String] = [],
        shouldAskUser: Bool = false
    ) {
        self.scene = scene
        self.stage = stage
        self.confidence = confidence
        self.reasons = reasons
        self.shouldAskUser = shouldAskUser
    }
}
