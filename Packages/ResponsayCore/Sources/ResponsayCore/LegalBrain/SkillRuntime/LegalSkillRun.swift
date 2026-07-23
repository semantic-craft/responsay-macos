import Foundation

// MARK: - 109 Privacy-safe skill-run log
//
// One row per executed skill. Stores only a HASH of the context + the routing
// metadata — never the raw selected text (unless the user later opts into history,
// spec §12). Lets the profile store show "what you've run" without retaining materials.

public struct LegalSkillRun: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let createdAt: Date
    public let contextHash: String      // hash of the selected text — never the text itself
    public let scene: LegalScene
    public let stage: LegalStage
    public let skillId: String
    public let modelRoute: ModelRoute

    public init(
        id: String,
        createdAt: Date,
        contextHash: String,
        scene: LegalScene,
        stage: LegalStage,
        skillId: String,
        modelRoute: ModelRoute
    ) {
        self.id = id
        self.createdAt = createdAt
        self.contextHash = contextHash
        self.scene = scene
        self.stage = stage
        self.skillId = skillId
        self.modelRoute = modelRoute
    }
}
