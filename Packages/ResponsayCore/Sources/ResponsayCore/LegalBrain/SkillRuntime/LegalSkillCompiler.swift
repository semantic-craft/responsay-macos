import Foundation

// MARK: - 102 LegalSkillCompiler
//
// Parses a `*.LEGAL_SKILL.md` file: the first ```legal-skill fenced block is
// strict JSON → `LegalSkillMetadata`; the remaining Markdown splits into the
// three instruction sections. Foundation-only (platform boundary as 101).

/// A compiled skill: decoded metadata + the three prompt sections + raw source.
public struct LegalSkillCompiled: Sendable, Identifiable, Equatable {
    public var id: String { metadata.id }
    public let metadata: LegalSkillMetadata
    public let skillInstructions: String
    public let reasoningProcedure: String
    public let outputConstraint: String
    public let rawMarkdown: String

    public init(
        metadata: LegalSkillMetadata,
        skillInstructions: String,
        reasoningProcedure: String,
        outputConstraint: String,
        rawMarkdown: String
    ) {
        self.metadata = metadata
        self.skillInstructions = skillInstructions
        self.reasoningProcedure = reasoningProcedure
        self.outputConstraint = outputConstraint
        self.rawMarkdown = rawMarkdown
    }

    public static func == (lhs: LegalSkillCompiled, rhs: LegalSkillCompiled) -> Bool {
        lhs.id == rhs.id && lhs.rawMarkdown == rhs.rawMarkdown
    }

    /// Filesystem-safe `<id>.LEGAL_SKILL.md` name — the single definition used both for the
    /// import directory (`FileImportedLegalSkillStore` delegates here) and as the 导出 save
    /// panel's default filename, so an exported file and a re-imported one agree byte-for-byte.
    public static func fileName(forID id: String) -> String {
        let safe = id
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(safe).LEGAL_SKILL.md"
    }

    /// Suggested filename when exporting this skill to disk.
    public var suggestedFileName: String { Self.fileName(forID: id) }
}

public enum LegalSkillCompileError: Error, Equatable {
    case missingMetadataBlock
    case invalidMetadataJSON(String)
    case emptyMandatoryMapping
    case emptyDisclaimer
    /// A `kind:rewrite` skill carries neither a `prompt` field nor a `## Skill
    /// Instructions` section — there is nothing to drive the rewrite (122).
    case emptyRewritePrompt
    /// The skill id collides with a bundled (or already-imported) skill.
    /// Rejected at import time (猎虫⑤ P1-1): persisting it poisoned the next
    /// launch — the registry merge threw, and the whole ⌥L palette died.
    case duplicateSkillID(String)
}

public struct LegalSkillCompiler: Sendable {
    public init() {}

    public func compile(_ markdown: String) throws -> LegalSkillCompiled {
        guard let json = Self.firstFencedBlock(markdown, language: "legal-skill") else {
            throw LegalSkillCompileError.missingMetadataBlock
        }
        let metadata: LegalSkillMetadata
        do {
            metadata = try JSONDecoder().decode(LegalSkillMetadata.self, from: Data(json.utf8))
        } catch {
            throw LegalSkillCompileError.invalidMetadataJSON(String(describing: error))
        }
        let body = Self.stripFirstFencedBlock(markdown, language: "legal-skill")
        let skillInstructions = Self.section("Skill Instructions", in: body)

        // Per-kind semantic gates (beyond JSON shape).
        switch metadata.kind {
        case .generation:
            // The reasoning kernel + disclaimer must carry content.
            guard !metadata.reasoningKernel.mandatoryMapping.isEmpty else {
                throw LegalSkillCompileError.emptyMandatoryMapping
            }
            guard !metadata.risk.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LegalSkillCompileError.emptyDisclaimer
            }
        case .rewrite:
            // A rewrite needs a prompt — either the `prompt` field or the instructions section.
            let effectivePrompt = metadata.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPrompt = !(effectivePrompt?.isEmpty ?? true)
                || !skillInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasPrompt else { throw LegalSkillCompileError.emptyRewritePrompt }
        }

        return LegalSkillCompiled(
            metadata: metadata,
            skillInstructions: skillInstructions,
            reasoningProcedure: Self.section("Reasoning Procedure", in: body),
            outputConstraint: Self.section("Output Constraint", in: body),
            rawMarkdown: markdown
        )
    }

    // MARK: - Markdown helpers

    static func firstFencedBlock(_ markdown: String, language: String) -> String? {
        var inBlock = false
        var collected: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if trimmed == "```\(language)" { inBlock = true }
            } else if trimmed == "```" {
                return collected.joined(separator: "\n")
            } else {
                collected.append(line)
            }
        }
        return nil
    }

    static func stripFirstFencedBlock(_ markdown: String, language: String) -> String {
        var output: [String] = []
        var inBlock = false
        var removed = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !removed, !inBlock, trimmed == "```\(language)" {
                inBlock = true
                continue
            }
            if inBlock {
                if trimmed == "```" { inBlock = false; removed = true }
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    /// Text under the first heading whose title contains `name`, up to the next heading.
    static func section(_ name: String, in markdown: String) -> String {
        var capturing = false
        var output: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                if capturing { break }
                if trimmed.lowercased().contains(name.lowercased()) { capturing = true }
                continue
            }
            if capturing { output.append(line) }
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
