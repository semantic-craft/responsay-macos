import Foundation

// MARK: - 106 LegalOutputValidator
//
// Turns the model's raw JSON text into a decodable `LegalSkillResponse`. The model
// authors the body (summary/cards/anchors/warnings); the client injects the envelope
// (schemaVersion/runId/skillId/scene/stage) before strict decode. On failure: one
// "fix JSON only" repair call; if still failing, a `FallbackTextCard` (no one-click
// insert, copy preserved). Never crashes, never fabricates an insert (spec §10).

public struct LegalOutputValidator: Sendable {
    public init() {}

    public struct Envelope: Sendable {
        public let runId: String
        public let skillId: String
        public let scene: LegalScene
        public let stage: LegalStage
        public init(runId: String, skillId: String, scene: LegalScene, stage: LegalStage) {
            self.runId = runId; self.skillId = skillId; self.scene = scene; self.stage = stage
        }
    }

    /// Decode `rawOutput`; on failure call `repair(brokenOutput)` once and retry; if it
    /// still fails, return a fallback response carrying the raw text.
    public func validate(
        rawOutput: String,
        envelope: Envelope,
        repair: (String) async throws -> String
    ) async -> LegalSkillResponse {
        if let decoded = decode(rawOutput, envelope: envelope) { return decoded }

        if let repaired = try? await repair(rawOutput), let decoded = decode(repaired, envelope: envelope) {
            return decoded
        }
        return Self.fallback(rawOutput, envelope: envelope)
    }

    /// Strict path: merge the envelope onto the model object, then `Codable`-decode.
    func decode(_ rawOutput: String, envelope: Envelope) -> LegalSkillResponse? {
        let stripped = Self.stripFences(rawOutput)
        guard let data = stripped.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        object["schemaVersion"] = LegalSkillResponse.schemaVersionV1
        object["runId"] = envelope.runId
        object["skillId"] = envelope.skillId
        object["scene"] = envelope.scene.rawValue
        object["stage"] = envelope.stage.rawValue

        guard let merged = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(LegalSkillResponse.self, from: merged)
        else { return nil }
        return decoded
    }

    /// The honest degrade: keep the model's prose as copyable text, disable insertion,
    /// and flag it so the renderer (107) never offers a one-click insert.
    static func fallback(_ rawOutput: String, envelope: Envelope) -> LegalSkillResponse {
        LegalSkillResponse(
            runId: envelope.runId,
            skillId: envelope.skillId,
            scene: envelope.scene,
            stage: envelope.stage,
            summary: "结构化输出解析失败，已降级为纯文本（请勿一键插入，可复制）。",
            cards: [.fallbackText(FallbackTextCard(title: "降级文本", text: Self.stripFences(rawOutput)))],
            insertables: [],
            verificationAnchors: [],
            warnings: ["LEGAL_OUTPUT 解析失败：已降级为纯文本并禁用一键插入。"])
    }

    /// Strip a leading/trailing ```json … ``` fence if the model added one.
    static func stripFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let firstNewline = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNewline)...]) }
        if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
