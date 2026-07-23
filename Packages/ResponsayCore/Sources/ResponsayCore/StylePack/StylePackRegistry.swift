import Foundation

/// Registers the built-in (practice-driven) style packs and any user-imported
/// ones, and filters them by scene/stage. Community packs are rejected in v0
/// (untrusted; spec §1.5/§2).
public struct StylePackRegistry: Sendable {
    public private(set) var packs: [StylePack]

    public init(packs: [StylePack] = StylePackRegistry.builtIns) {
        self.packs = packs.filter { $0.origin != .community }
    }

    public func pack(id: String) -> StylePack? { packs.first { $0.id == id } }

    /// The bundled `style.*` LEGAL_SKILL.md files (kind:rewrite) as built-in style
    /// packs (325). These are the home the bundled style skills moved to when they
    /// were removed from the ⌥L generation palette (slice 3b). Generation skills in
    /// the same bundle are ignored.
    public static func bundled(
        compiler: LegalSkillCompiler = LegalSkillCompiler()
    ) throws -> StylePackRegistry {
        guard let directory = LegalSkillRegistry.bundledSkillsDirectory() else {
            throw LegalSkillRegistryError.bundleResourceMissing
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let packs = urls
            .filter { $0.lastPathComponent.hasSuffix(".LEGAL_SKILL.md") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? compiler.compile(try String(contentsOf: $0, encoding: .utf8)) }
            .filter { $0.metadata.kind == .rewrite }
            .map { StylePack.from($0, origin: .builtIn) }
        return StylePackRegistry(packs: packs)
    }

    /// Packs offered for a scene/stage (a pack with `.any` scope always shows).
    public func packs(forScene scene: LegalScene, stage: LegalStage) -> [StylePack] {
        packs.filter { $0.scope.matches(scene: scene, stage: stage) }
    }

    /// Add a pack — built-in or local import only. A `.community` pack is dropped
    /// (returns the registry unchanged) since v0 keeps the marketplace off.
    public func registering(_ pack: StylePack) -> StylePackRegistry {
        guard pack.origin != .community else { return self }
        var next = packs.filter { $0.id != pack.id }
        next.append(pack)
        return StylePackRegistry(packs: next)
    }

    // MARK: - Built-ins (register-shaping only; never introduce facts)

    public static let builtIns: [StylePack] = [
        StylePack(
            id: "general.clear", name: "通用 · 清晰改写",
            systemPrompt: "在不改变原意与事实的前提下，让表达更清晰、连贯、得体；不新增任何法条/案号/日期等事实坐标。",
            scope: .any
        ),
        StylePack(
            id: "litigation.adversarial", name: "对抗性文书体",
            systemPrompt: "采用诉讼对抗语域：立场明确、论点紧凑、攻防有序；只重排与强化既有论据，不杜撰证据或法律依据。",
            scope: StylePackScope(scenes: [.litigation], stages: [.briefDrafting, .argumentDrafting])
        ),
        StylePack(
            id: "legal.memo", name: "法律意见 · 备忘录体",
            systemPrompt: "采用法律备忘录语域：结论先行、要点分层、措辞审慎克制；保留全部既有事实坐标，不替用户下未经核验的结论。",
            scope: StylePackScope(scenes: [.litigation, .contract], stages: [.briefDrafting])
        ),
        StylePack(
            id: "legal.elements", name: "要件涵摄体",
            systemPrompt: "采用要件—事实涵摄语域：逐要件对应事实、显式给出涵摄链条；不补充缺失要件事实，缺口如实标注。",
            scope: StylePackScope(stages: [.claimChart, .argumentDrafting])
        ),
        StylePack(
            id: "business.plain", name: "业务白话摘要体",
            systemPrompt: "面向业务方的白话语域：去术语、讲清影响与下一步；不弱化风险、不省略既有合规约束。",
            scope: StylePackScope(scenes: [.productCompliance, .contract])
        ),
        StylePack(
            id: "academic.argument", name: "法学论证体",
            systemPrompt: "采用法学论证语域：命题—理由—反驳—回应层层推进、概念边界清晰；不虚构文献、判例或页码。",
            scope: StylePackScope(scenes: [.academicWriting], stages: [.argumentDrafting, .literatureReview])
        ),
        StylePack(
            id: "compliance.clause", name: "合规条款体",
            systemPrompt: "采用合规条款语域：义务主体、行为、例外与后果表述精确、可执行；不放宽既有义务、不新增未经核验的标准引用。",
            scope: StylePackScope(scenes: [.productCompliance, .privacy], stages: [.productReview, .piaTriage])
        ),
    ]
}
