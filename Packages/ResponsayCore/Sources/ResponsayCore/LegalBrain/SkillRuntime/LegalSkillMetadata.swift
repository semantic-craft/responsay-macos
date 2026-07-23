import Foundation

// MARK: - LEGAL_SKILL metadata
//
// The strict-JSON metadata block of a `*.LEGAL_SKILL.md` file. The compiler (issue 102)
// decodes the first ```legal-skill fenced block into `LegalSkillMetadata`; the remaining
// Markdown becomes the instruction prompt. See spec §4–§7.

/// Fields a skill is allowed to consume from `ExpressionContext` + derived inputs.
public enum LegalSkillInputField: String, Codable, Sendable, CaseIterable {
    case selectedText
    case textBeforeCursor
    case textAfterCursor
    case appName
    case windowTitle
    case hotwords
    case userProfile
    case factCoordinates
}

/// What triggers a skill as a candidate (rules-first, no model). See router (issue 104).
public struct LegalSkillTriggers: Codable, Sendable {
    public let keywords: [String]
    public let appHints: [String]
    public let windowTitleHints: [String]
    public let minSelectedTextLength: Int

    public init(
        keywords: [String] = [],
        appHints: [String] = [],
        windowTitleHints: [String] = [],
        minSelectedTextLength: Int = 0
    ) {
        self.keywords = keywords
        self.appHints = appHints
        self.windowTitleHints = windowTitleHints
        self.minSelectedTextLength = minSelectedTextLength
    }
}

/// Vertical "场景层" — which scene/stage this skill serves and what comes next.
public struct SceneLayer: Codable, Sendable {
    public let scene: LegalScene
    public let applicableStages: [LegalStage]
    public let preconditions: [String]
    public let nextActionCandidates: [String]

    public init(
        scene: LegalScene,
        applicableStages: [LegalStage] = [],
        preconditions: [String] = [],
        nextActionCandidates: [String] = []
    ) {
        self.scene = scene
        self.applicableStages = applicableStages
        self.preconditions = preconditions
        self.nextActionCandidates = nextActionCandidates
    }

    enum CodingKeys: String, CodingKey {
        case scene, applicableStages, preconditions, nextActionCandidates
    }

    // Only `scene` is required; the array fields default to empty so lightweight
    // (rewrite) skills don't have to write boilerplate (122/237).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scene = try c.decode(LegalScene.self, forKey: .scene)
        applicableStages = try c.decodeIfPresent([LegalStage].self, forKey: .applicableStages) ?? []
        preconditions = try c.decodeIfPresent([String].self, forKey: .preconditions) ?? []
        nextActionCandidates = try c.decodeIfPresent([String].self, forKey: .nextActionCandidates) ?? []
    }
}

/// Horizontal "推理内核" — the mandatory reasoning mapping the model must fill, plus
/// hard prohibitions. Authored from public 法学 doctrine; see issue 103 license note.
public struct ReasoningKernel: Codable, Sendable {
    public let mandatoryMapping: [String]
    public let forbidden: [String]

    public init(mandatoryMapping: [String], forbidden: [String] = []) {
        self.mandatoryMapping = mandatoryMapping
        self.forbidden = forbidden
    }
}

/// Output card kinds a skill may emit. Renderer (issue 107) consumes these.
public enum LegalOutputCardType: String, Codable, Sendable, CaseIterable {
    case evidenceArgumentMatrix
    case claimEvidenceMap
    case counterargument
    case nextStepDecisionTree
    case verificationTodos
    case cnkiQuery
    case conceptMap
    case riskMatrix
    case insertableParagraph
    case fallbackText
    case legalAnalysis
    case strategyRecommendation
    case caseFacts            // 487 — LLM 抽取的检索焦点（被 post-processor 替换为作战图）
    case caseRetrievalReport  // 487 — app 渲染的检索作战图
}

public enum LegalSkillRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct LegalSkillRisk: Codable, Sendable {
    public let level: LegalSkillRiskLevel
    public let disclaimer: String

    public init(level: LegalSkillRiskLevel, disclaimer: String) {
        self.level = level
        self.disclaimer = disclaimer
    }
}

/// Which tier of the Legal Skill Platform a skill belongs to (122). `rewrite` skills
/// shape a legal-text rewrite register (≈ openless 风格包: prompt + few-shot examples)
/// and map to `StylePack`; `generation` skills are the full v1 (triggers / reasoning
/// kernel / output cards / risk) and map to `LegalSkillCompiled`. Tolerant decode +
/// default `.generation` so the existing corpus (no `kind`) keeps loading unchanged.
public enum LegalSkillKind: String, Codable, Sendable, Equatable {
    case generation
    case rewrite

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // A PRESENT but unknown kind is an author error, not a default (猎虫⑤
        // P2-1): `kind:"rewite"` used to collapse silently into .generation and
        // the author got the misleading 「生成技能缺少推理内核」. An ABSENT kind
        // still defaults to .generation elsewhere (the shipped corpus has none).
        guard let kind = LegalSkillKind(rawValue: raw.lowercased()) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown legal-skill kind \"\(raw)\" (expected rewrite|generation)"))
        }
        self = kind
    }
}

/// How a skill interacts once the user picks it from the 划词菜单: a one-shot result
/// card (`LegalSkillOutputView`) or a multi-turn conversation in the Voice Assistant.
/// Tolerant default `.oneShot` so the existing corpus (no `interaction`) keeps loading
/// unchanged; only skills that genuinely need back-and-forth declare `conversation`.
/// A PRESENT but unknown value throws (author error), matching `kind`/`outputCards`.
public enum SkillInteraction: String, Codable, Sendable, Equatable {
    case oneShot
    case conversation
}

/// A few-shot input/output example a rewrite skill carries (aligns with openless
/// `StylePackExample`). Reused by `StylePack.examples`.
public struct LegalSkillExample: Codable, Sendable, Equatable {
    public let title: String?
    public let input: String
    public let output: String

    public init(title: String? = nil, input: String, output: String) {
        self.title = title
        self.input = input
        self.output = output
    }
}

/// Decoded metadata for one skill. Heavy generation-only fields (triggers / sceneLayer /
/// reasoningKernel / outputCards / risk) decode-with-default so a `kind:rewrite` skill may
/// omit them; the compiler's per-kind semantic gates (102) enforce what each kind needs.
public struct LegalSkillMetadata: Codable, Sendable, Identifiable {
    public let schemaVersion: String
    public let id: String
    public let title: String
    public let domain: LegalScene
    public let language: String
    public let kind: LegalSkillKind
    /// How the skill engages after selection (one-shot card vs multi-turn). Default `.oneShot`.
    public let interaction: SkillInteraction
    /// rewrite tier: which 技能平台 lane(s) offer this style pack. Absent in the file → both
    /// lanes, so imported third-party packs behave exactly as before. Unused by generation.
    public let lanes: [SkillLane]
    /// rewrite tier: the system prompt (or `nil` → the compiler falls back to the
    /// `## Skill Instructions` section). Unused by generation.
    public let prompt: String?
    /// rewrite tier: few-shot examples. Empty for generation.
    public let examples: [LegalSkillExample]
    public let triggers: LegalSkillTriggers
    public let inputs: [LegalSkillInputField]
    public let sceneLayer: SceneLayer
    public let reasoningKernel: ReasoningKernel
    public let outputCards: [LegalOutputCardType]
    public let risk: LegalSkillRisk

    // MARK: Presentation & Curation
    public let description: String?
    public let author: String?
    public let version: String?
    public let tags: [String]
    public let icon: String?

    // MARK: Execution Constraints
    public let recommendedModel: String?
    public let compatibleAppVersion: String?

    // MARK: Marketplace Lineage
    public let originSkillId: String?
    public let originAuthor: String?

    public init(
        schemaVersion: String,
        id: String,
        title: String,
        domain: LegalScene,
        language: String,
        kind: LegalSkillKind = .generation,
        interaction: SkillInteraction = .oneShot,
        lanes: [SkillLane] = SkillLane.allCases,
        prompt: String? = nil,
        examples: [LegalSkillExample] = [],
        triggers: LegalSkillTriggers,
        inputs: [LegalSkillInputField],
        sceneLayer: SceneLayer,
        reasoningKernel: ReasoningKernel,
        outputCards: [LegalOutputCardType],
        risk: LegalSkillRisk,
        description: String? = nil,
        author: String? = nil,
        version: String? = nil,
        tags: [String] = [],
        icon: String? = nil,
        recommendedModel: String? = nil,
        compatibleAppVersion: String? = nil,
        originSkillId: String? = nil,
        originAuthor: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.domain = domain
        self.language = language
        self.kind = kind
        self.interaction = interaction
        self.lanes = lanes
        self.prompt = prompt
        self.examples = examples
        self.triggers = triggers
        self.inputs = inputs
        self.sceneLayer = sceneLayer
        self.reasoningKernel = reasoningKernel
        self.outputCards = outputCards
        self.risk = risk
        self.description = description
        self.author = author
        self.version = version
        self.tags = tags
        self.icon = icon
        self.recommendedModel = recommendedModel
        self.compatibleAppVersion = compatibleAppVersion
        self.originSkillId = originSkillId
        self.originAuthor = originAuthor
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, domain, language, kind, interaction, lanes, prompt, examples
        case triggers, inputs, sceneLayer, reasoningKernel, outputCards, risk
        case description, author, version, tags, icon
        case recommendedModel, compatibleAppVersion
        case originSkillId, originAuthor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        domain = try c.decode(LegalScene.self, forKey: .domain)
        language = try c.decode(String.self, forKey: .language)
        kind = try c.decodeIfPresent(LegalSkillKind.self, forKey: .kind) ?? .generation
        interaction = try c.decodeIfPresent(SkillInteraction.self, forKey: .interaction) ?? .oneShot
        // Absent → both lanes: an imported pack that predates this field must not vanish from
        // either list. Empty array is treated the same way (a pack offered nowhere is a bug).
        let declaredLanes = try c.decodeIfPresent([SkillLane].self, forKey: .lanes) ?? []
        lanes = declaredLanes.isEmpty ? SkillLane.allCases : declaredLanes
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        examples = try c.decodeIfPresent([LegalSkillExample].self, forKey: .examples) ?? []
        triggers = try c.decodeIfPresent(LegalSkillTriggers.self, forKey: .triggers) ?? LegalSkillTriggers()
        inputs = try c.decodeIfPresent([LegalSkillInputField].self, forKey: .inputs) ?? []
        sceneLayer = try c.decodeIfPresent(SceneLayer.self, forKey: .sceneLayer) ?? SceneLayer(scene: domain)
        reasoningKernel = try c.decodeIfPresent(ReasoningKernel.self, forKey: .reasoningKernel)
            ?? ReasoningKernel(mandatoryMapping: [])
        outputCards = try c.decodeIfPresent([LegalOutputCardType].self, forKey: .outputCards) ?? []
        risk = try c.decodeIfPresent(LegalSkillRisk.self, forKey: .risk)
            ?? LegalSkillRisk(level: .low, disclaimer: "")
        description = try c.decodeIfPresent(String.self, forKey: .description)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        recommendedModel = try c.decodeIfPresent(String.self, forKey: .recommendedModel)
        compatibleAppVersion = try c.decodeIfPresent(String.self, forKey: .compatibleAppVersion)
        originSkillId = try c.decodeIfPresent(String.self, forKey: .originSkillId)
        originAuthor = try c.decodeIfPresent(String.self, forKey: .originAuthor)
    }
}

/// A skill as loaded from disk: metadata + the raw markdown + the instruction body.
/// The compiled prompt form (`Skill Instructions` / `Reasoning Procedure` /
/// `Output Constraint`) is the compiler's job (issue 102).
public struct LegalSkillSource: Codable, Sendable, Identifiable {
    public let id: String
    public let rawMarkdown: String
    public let metadata: LegalSkillMetadata
    public let instructionMarkdown: String

    public init(rawMarkdown: String, metadata: LegalSkillMetadata, instructionMarkdown: String) {
        self.id = metadata.id
        self.rawMarkdown = rawMarkdown
        self.metadata = metadata
        self.instructionMarkdown = instructionMarkdown
    }
}
