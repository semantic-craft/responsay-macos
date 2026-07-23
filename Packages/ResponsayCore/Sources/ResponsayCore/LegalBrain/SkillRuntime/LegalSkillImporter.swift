import Foundation

// MARK: - 122 LegalSkillImporter
//
// The seam the import UI calls: compile an imported `*.LEGAL_SKILL.md`, route by `kind`
// (rewrite → StylePack for the rewrite picker; generation → LegalSkillCompiled for the
// ⌥L registry), persist the raw markdown to the user skill directory via an injected
// store, and fail cleanly on bad content. Imported skills are NOT auto-enabled — they
// only appear after the user enables them in Settings (220 enabled-set).

/// Persistence seam for imported skills (user skill directory). Injected so the importer
/// is testable without touching the real filesystem.
public protocol ImportedLegalSkillStore {
    func save(rawMarkdown: String, id: String) throws
    func loadAllRawMarkdown() throws -> [String]
}

/// The result of importing one file.
public enum LegalSkillImportOutcome {
    case rewrite(StylePack)
    case generation(LegalSkillCompiled)
    case failed(LegalSkillCompileError)
}

public struct LegalSkillImporter {
    private let compiler: LegalSkillCompiler
    private let store: ImportedLegalSkillStore?
    private let reservedIDs: () -> Set<String>

    /// `reservedIDs` defaults to the bundled corpus ids — an import colliding
    /// with a bundled skill is rejected up front (猎虫⑤ P1-1). Re-importing the
    /// SAME imported id stays allowed: that is the update path (last-wins).
    public init(
        compiler: LegalSkillCompiler = LegalSkillCompiler(),
        store: ImportedLegalSkillStore? = nil,
        reservedIDs: @escaping () -> Set<String> = {
            Set(((try? LegalSkillRegistry.loadBundled())?.skills ?? []).map(\.id))
        }
    ) {
        self.compiler = compiler
        self.store = store
        self.reservedIDs = reservedIDs
    }

    public func importSkill(markdown: String) -> LegalSkillImportOutcome {
        let compiled: LegalSkillCompiled
        do {
            compiled = try compiler.compile(markdown)
        } catch let error as LegalSkillCompileError {
            return .failed(error)
        } catch {
            return .failed(.invalidMetadataJSON(String(describing: error)))
        }
        if reservedIDs().contains(compiled.id) {
            return .failed(.duplicateSkillID(compiled.id))
        }

        do {
            try store?.save(rawMarkdown: markdown, id: compiled.id)
        } catch {
            // A successfully-compiled skill that can't be persisted is still a hard failure —
            // the user would otherwise see "imported" but lose it on relaunch.
            return .failed(.invalidMetadataJSON("persist failed: \(error)"))
        }

        switch compiled.metadata.kind {
        case .rewrite:    return .rewrite(Self.stylePack(from: compiled))
        case .generation: return .generation(compiled)
        }
    }

    /// Map a compiled rewrite skill to a local-import StylePack (register-only).
    /// Shares the mapping with the bundled loader via `StylePack.from` (325).
    static func stylePack(from compiled: LegalSkillCompiled) -> StylePack {
        StylePack.from(compiled, origin: .localImport)
    }
}
