import Foundation

/// Provenance of a style pack — drives the trust boundary. Community packs are
/// untrusted system prompts → off in v0 (spec §1.5/§2).
public enum StylePackOrigin: String, Codable, Sendable, CaseIterable {
    case builtIn
    case localImport
    case community
}

/// Where a pack is offered. Empty arrays = applies to any scene/stage.
public struct StylePackScope: Codable, Sendable, Equatable {
    public var scenes: [LegalScene]
    public var stages: [LegalStage]

    public init(scenes: [LegalScene] = [], stages: [LegalStage] = []) {
        self.scenes = scenes
        self.stages = stages
    }

    public static let any = StylePackScope()

    public func matches(scene: LegalScene, stage: LegalStage) -> Bool {
        (scenes.isEmpty || scenes.contains(scene)) && (stages.isEmpty || stages.contains(stage))
    }
}

/// A style pack shapes **register only** — it is a system prompt that composes
/// orthogonally with the LEGAL_SKILL runtime and cannot carry routing/privacy
/// fields (so it structurally cannot change `ModelRoute` / send-scope). It
/// attaches at the `PromptAssembler` + output post-pass only (spec §1.5/§6).
public struct StylePack: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let systemPrompt: String
    public let scope: StylePackScope
    public let origin: StylePackOrigin
    /// Few-shot examples carried by a rewrite-tier skill (122; aligns with openless
    /// `StylePackExample`). Empty for the register-only built-ins.
    public let examples: [LegalSkillExample]

    public init(
        id: String,
        name: String,
        systemPrompt: String,
        scope: StylePackScope = .any,
        origin: StylePackOrigin = .builtIn,
        examples: [LegalSkillExample] = []
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.scope = scope
        self.origin = origin
        self.examples = examples
    }

    enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt, scope, origin, examples
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        scope = try c.decodeIfPresent(StylePackScope.self, forKey: .scope) ?? .any
        origin = try c.decodeIfPresent(StylePackOrigin.self, forKey: .origin) ?? .builtIn
        examples = try c.decodeIfPresent([LegalSkillExample].self, forKey: .examples) ?? []
    }

    /// Map a compiled `kind:rewrite` LEGAL_SKILL into a register-only StylePack
    /// (325). The systemPrompt is the skill's `prompt` field, or its `## Skill
    /// Instructions` section when `prompt` is absent. Shared by the importer
    /// (`.localImport`) and the bundled loader (`.builtIn`).
    public static func from(_ compiled: LegalSkillCompiled, origin: StylePackOrigin) -> StylePack {
        let meta = compiled.metadata
        let trimmed = meta.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = (trimmed?.isEmpty == false) ? meta.prompt! : compiled.skillInstructions
        return StylePack(
            id: meta.id,
            name: meta.title,
            systemPrompt: systemPrompt,
            scope: StylePackScope(scenes: [meta.domain], stages: meta.sceneLayer.applicableStages),
            origin: origin,
            examples: meta.examples)
    }
}
