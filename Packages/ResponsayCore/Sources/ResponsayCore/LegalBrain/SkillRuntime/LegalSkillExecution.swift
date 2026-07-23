import Foundation

// MARK: - 106 Legal skill execution wire contract
//
// The request/response exchanged with the backend `/legal/skill/execute` route.
// The prompt is assembled CLIENT-side (the skill corpus lives in `Bundle.module`,
// 103) and sent verbatim; the backend is a thin model-call passthrough that honors
// the model route and returns the model's raw JSON text for the validator (106).

public struct LegalSkillExecutionRequest: Codable, Sendable {
    public let skillId: String
    public let systemPrompt: String
    public let userPrompt: String
    /// Privacy/route decision (110). `localOnly` MUST NOT reach cloud (backend-enforced too).
    public let modelRoute: ModelRoute
    public let purpose: ModelPurpose
    /// Optional provider / token-plan / model overrides (mirrors the coach routes).
    public let provider: String?
    public let textRoute: String?
    public let model: String?
    /// True when this is a "fix the JSON only" repair pass (validator second call).
    public let isRepair: Bool

    public init(
        skillId: String,
        systemPrompt: String,
        userPrompt: String,
        modelRoute: ModelRoute,
        purpose: ModelPurpose = .legalSkill,
        provider: String? = nil,
        textRoute: String? = nil,
        model: String? = nil,
        isRepair: Bool = false
    ) {
        self.skillId = skillId
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.modelRoute = modelRoute
        self.purpose = purpose
        self.provider = provider
        self.textRoute = textRoute
        self.model = model
        self.isRepair = isRepair
    }

    /// The body the backend expects (kept explicit so the wire shape is reviewable).
    public var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "skillId": skillId,
            "systemPrompt": systemPrompt,
            "userPrompt": userPrompt,
            "modelRoute": modelRoute.rawValue,
            "purpose": purpose.rawValue,
            "isRepair": isRepair,
        ]
        if let provider { object["provider"] = provider }
        if let textRoute { object["route"] = textRoute }
        if let model { object["model"] = model }
        return object
    }
}

/// The backend's reply: the model's raw JSON text plus the envelope the client fills
/// (so the core never needs `UUID()`/`Date()` — the backend supplies `runId`).
public struct LegalSkillExecutionResponse: Codable, Sendable {
    public let output: String
    public let runId: String
    public let provider: String?
    public let route: String?

    public init(output: String, runId: String, provider: String? = nil, route: String? = nil) {
        self.output = output
        self.runId = runId
        self.provider = provider
        self.route = route
    }
}
