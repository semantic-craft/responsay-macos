import Foundation

// MARK: - 122 FileImportedLegalSkillStore
//
// On-disk persistence for imported skills: one `*.LEGAL_SKILL.md` per skill in the user
// skill directory (Application Support/Responsay/LegalSkills), kept separate from the
// read-only bundled corpus. The app loads both at startup; only this user directory is
// writable.

public struct FileImportedLegalSkillStore: ImportedLegalSkillStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init() {
        self.init(directory: Self.defaultDirectory)
    }

    /// `~/Library/Application Support/Responsay/LegalSkills` — the writable user skill area.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Responsay/LegalSkills", isDirectory: true)
    }

    public func save(rawMarkdown: String, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Self.fileName(for: id))")
        try rawMarkdown.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Remove an imported skill's file. Used when an in-app edit changes the skill id, so the
    /// old id's file doesn't orphan alongside the new one. No-op if the file is absent.
    public func delete(id: String) throws {
        let url = directory.appendingPathComponent(Self.fileName(for: id))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadAllRawMarkdown() throws -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.lastPathComponent.hasSuffix(".LEGAL_SKILL.md") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            // Per-file resilience (猎虫⑤ P1-2): one unreadable/non-UTF-8 file used
            // to throw the whole load — every caller swallows with `try?`, so ALL
            // imported skills silently vanished together. Skip the bad file only,
            // matching the runtime's treatment of files that fail to compile.
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// A filesystem-safe filename derived from the skill id. Single definition lives on
    /// `LegalSkillCompiled` so an exported file and the import directory agree.
    static func fileName(for id: String) -> String {
        LegalSkillCompiled.fileName(forID: id)
    }
}
