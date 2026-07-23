import Foundation

// MARK: - ContextSignalLayer (issues 113–117)
//
// A deterministic, no-LLM signal layer between `ExpressionContext` and the scene
// router (104). Foundation-only (platform boundary as 101). Every type reuses the
// built issue-101 schema (`LegalScene`/`LegalStage`/`SceneStageClassification`/
// `VerificationSourcePreference`) — no forked enums.

/// A weighted scene prior with a human-readable reason, contributed by a signal
/// producer. `scene` is the **built** `LegalScene`.
public struct LegalScenePrior: Codable, Sendable, Equatable {
    public let scene: LegalScene
    public let weight: Double
    public let reason: String

    public init(scene: LegalScene, weight: Double, reason: String = "") {
        self.scene = scene
        self.weight = weight
        self.reason = reason
    }
}
