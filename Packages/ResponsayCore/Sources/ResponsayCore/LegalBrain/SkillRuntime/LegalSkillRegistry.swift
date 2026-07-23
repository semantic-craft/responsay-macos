import Foundation

// MARK: - 102 LegalSkillRegistry
//
// Indexes compiled skills so the router (104) can suggest candidates for a
// (scene, stage, keywords) query. Enforces unique ids at build time.

public enum LegalSkillRegistryError: Error, Equatable {
    case duplicateID(String)
    case bundleResourceMissing
}

public struct LegalSkillRegistry: Sendable {
    public let skills: [LegalSkillCompiled]
    private let byID: [String: LegalSkillCompiled]

    public init(_ skills: [LegalSkillCompiled]) throws {
        var byID: [String: LegalSkillCompiled] = [:]
        for skill in skills {
            if byID[skill.id] != nil { throw LegalSkillRegistryError.duplicateID(skill.id) }
            byID[skill.id] = skill
        }
        self.skills = skills
        self.byID = byID
    }

    public func skill(id: String) -> LegalSkillCompiled? { byID[id] }

    /// Return a new registry that also indexes `imported` skills (122/235). Throws
    /// `duplicateID` if an imported id collides with a bundled one (no silent override).
    public func merging(_ imported: [LegalSkillCompiled]) throws -> LegalSkillRegistry {
        try LegalSkillRegistry(skills + imported)
    }

    /// Candidate skills for a query. A skill matches when its scene matches,
    /// the stage is applicable (or the skill lists no stages = any), and any
    /// trigger keyword overlaps (when keywords are supplied). Ordered by
    /// keyword-match count (desc) then id, so results are deterministic.
    public func candidates(
        scene: LegalScene,
        stage: LegalStage? = nil,
        keywords: [String] = []
    ) -> [LegalSkillCompiled] {
        let queryKeywords = Set(keywords.map { $0.lowercased() })
        return skills
            .compactMap { skill -> (LegalSkillCompiled, Int)? in
                let meta = skill.metadata
                // 325 slice 3b: rewrite-kind skills are 改写风格 packs, never ⌥L
                // generation candidates — without this they surfaced in the palette
                // and were mis-executed as generation skills.
                guard meta.kind == .generation else { return nil }
                let sceneOK = meta.sceneLayer.scene == scene || meta.domain == scene
                guard sceneOK else { return nil }

                if let stage {
                    let stages = meta.sceneLayer.applicableStages
                    guard stages.isEmpty || stages.contains(stage) else { return nil }
                }

                let skillKeywords = Set(meta.triggers.keywords.map { $0.lowercased() })
                let overlap = queryKeywords.intersection(skillKeywords).count
                if !queryKeywords.isEmpty, overlap == 0 { return nil }
                return (skill, overlap)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.id < rhs.0.id
            }
            .map(\.0)
    }

    /// Compile + index every `*.LEGAL_SKILL.md` in a directory (e.g. the app
    /// bundle's `LegalSkills/`). Resource wiring into `Package.swift`/the app
    /// bundle is the follow-up (103 authors the skills).
    public static func loadBundledSkills(
        from directory: URL,
        compiler: LegalSkillCompiler = LegalSkillCompiler()
    ) throws -> LegalSkillRegistry {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let skillFiles = urls
            .filter { $0.lastPathComponent.hasSuffix(".LEGAL_SKILL.md") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let compiled = try skillFiles.map { try compiler.compile(try String(contentsOf: $0, encoding: .utf8)) }
        return try LegalSkillRegistry(compiled)
    }

    /// The `LegalSkills/` directory shipped inside `ResponsayCore`'s resource bundle
    /// (the v0 corpus authored in issue 103). Resolves in both the SwiftPM test bundle
    /// and the embedded app bundle.
    public static func bundledSkillsDirectory() -> URL? {
        Bundle.module.url(forResource: "LegalSkills", withExtension: nil)
    }

    /// Compile + index the bundled v0 corpus. Convenience for the executor (106) /
    /// router host (104) so they don't each re-discover the resource path.
    public static func loadBundled(
        compiler: LegalSkillCompiler = LegalSkillCompiler()
    ) throws -> LegalSkillRegistry {
        guard let directory = bundledSkillsDirectory() else {
            throw LegalSkillRegistryError.bundleResourceMissing
        }
        return try loadBundledSkills(from: directory, compiler: compiler)
    }
}
