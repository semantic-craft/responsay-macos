import Foundation

// MARK: - 188 MatterStore — folder-backed, default-off
//
// Source of truth per matter = `matters/<slug>/matter.json` (robust Codable). Human views:
// `matter.md` (generated) + `history.md` (append-only). `matters/_log.yaml` = generated rollup
// (emit-only). Global state (enabled + active slug) in `matters/_state.json`.
//
// DEFAULT OFF: a fresh root is disabled with no active matter, so `activeMatter()` is nil and
// skills stay stateless (the PromptAssembler provider, 191, gates on this). Foundation-only
// (platform boundary, as 101): no AppKit/AX/CGEvent/SwiftUI.

public enum MatterStoreError: Error, Equatable {
    case slugInUse(String)
    case unknownSlug(String)
    case invalidSlug(String)
}

/// The only global mutable state: whether the workspace is on, and which matter is active.
public struct MatterWorkspaceState: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var activeSlug: String?
    public init(enabled: Bool = false, activeSlug: String? = nil) {
        self.enabled = enabled
        self.activeSlug = activeSlug
    }
}

public final class MatterStore {
    private let root: URL
    private let fm = FileManager.default

    /// `root` is the `matters/` directory (created lazily on first write).
    public init(root: URL) { self.root = root }

    // MARK: - Paths
    private var stateURL: URL { root.appendingPathComponent("_state.json") }
    private var ledgerURL: URL { root.appendingPathComponent("_log.yaml") }
    private var archiveDir: URL { root.appendingPathComponent("_archived", isDirectory: true) }
    private func matterDir(_ slug: String) -> URL { root.appendingPathComponent(slug, isDirectory: true) }
    private func matterJSON(_ slug: String) -> URL { matterDir(slug).appendingPathComponent("matter.json") }
    private func matterMD(_ slug: String) -> URL { matterDir(slug).appendingPathComponent("matter.md") }

    // MARK: - Enabled / active state
    public func state() -> MatterWorkspaceState {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(MatterWorkspaceState.self, from: data)
        else { return MatterWorkspaceState() }   // default OFF
        return s
    }

    public var isEnabled: Bool { state().enabled }

    public func setEnabled(_ on: Bool) throws {
        var s = state(); s.enabled = on; try writeState(s)
    }

    /// The active matter, or nil when the layer is off / detached. The gate that keeps skills
    /// stateless by default.
    public func activeMatter() -> Matter? {
        let s = state()
        guard s.enabled, let slug = s.activeSlug else { return nil }
        return try? load(slug)
    }

    public func switchActive(to slug: String) throws {
        guard fm.fileExists(atPath: matterJSON(slug).path) else { throw MatterStoreError.unknownSlug(slug) }
        var s = state(); s.enabled = true; s.activeSlug = slug
        try writeState(s); try regenerateLedger()
    }

    /// Practice-level only ("none"): detach from any active matter without disabling.
    public func detach() throws {
        var s = state(); s.activeSlug = nil
        try writeState(s); try regenerateLedger()
    }

    // MARK: - CRUD
    public func create(_ matter: Matter) throws {
        try Self.validateSlug(matter.slug)
        guard !fm.fileExists(atPath: matterDir(matter.slug).path),
              !fm.fileExists(atPath: archiveDir.appendingPathComponent(matter.slug).path)
        else { throw MatterStoreError.slugInUse(matter.slug) }
        try fm.createDirectory(at: matterDir(matter.slug), withIntermediateDirectories: true)
        try writeFiles(matter)
        try appendHistory(matter.slug, event: "Opened", at: matter.createdAt, detail: "Intake: \(matter.title)")
        try setEnabled(true)        // creating a matter opts in — but does NOT auto-switch
        try regenerateLedger()
    }

    public func load(_ slug: String) throws -> Matter {
        let url = fm.fileExists(atPath: matterJSON(slug).path)
            ? matterJSON(slug)
            : archiveDir.appendingPathComponent(slug, isDirectory: true).appendingPathComponent("matter.json")
        guard let data = try? Data(contentsOf: url) else { throw MatterStoreError.unknownSlug(slug) }
        return try JSONDecoder().decode(Matter.self, from: data)
    }

    /// Persist an updated matter (source of truth = matter.json; matter.md regenerated).
    public func write(_ matter: Matter) throws {
        guard fm.fileExists(atPath: matterDir(matter.slug).path) else { throw MatterStoreError.unknownSlug(matter.slug) }
        try writeFiles(matter)
        try regenerateLedger()
    }

    public func list(includeArchived: Bool = false) -> [MatterLedgerEntry] {
        var entries = scan(dir: root)
        if includeArchived { entries += scan(dir: archiveDir) }
        return entries.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// Archive (never delete): move to `_archived/<slug>/`, mark closed, log it.
    public func close(_ slug: String, at when: String) throws {
        guard fm.fileExists(atPath: matterDir(slug).path) else { throw MatterStoreError.unknownSlug(slug) }
        var m = try load(slug)
        m.status = .archived; m.stage = .closed; m.updatedAt = when
        try Data(jsonData(m)).write(to: matterJSON(slug), options: .atomic)
        try appendHistory(slug, event: "Closed", at: when, detail: nil)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let dest = archiveDir.appendingPathComponent(slug, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: matterDir(slug), to: dest)
        var s = state(); if s.activeSlug == slug { s.activeSlug = nil; try writeState(s) }
        try regenerateLedger()
    }

    /// Append-only history (oldest-first). Works for active and archived matters.
    public func appendHistory(_ slug: String, event: String, at when: String, detail: String?) throws {
        let dir = fm.fileExists(atPath: matterDir(slug).path)
            ? matterDir(slug)
            : archiveDir.appendingPathComponent(slug, isDirectory: true)
        let url = dir.appendingPathComponent("history.md")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? "# History — \(slug)\n\n_Append-only event log._\n"
        var entry = "\n## \(when) — \(event)\n"
        if let detail { entry += "\n\(detail)\n" }
        try Data((existing + entry).utf8).write(to: url, options: .atomic)
    }

    // MARK: - Internals
    private func writeFiles(_ matter: Matter) throws {
        try fm.createDirectory(at: matterDir(matter.slug), withIntermediateDirectories: true)
        try Data(jsonData(matter)).write(to: matterJSON(matter.slug), options: .atomic)
        try Data(matter.markdownView().utf8).write(to: matterMD(matter.slug), options: .atomic)
    }

    private func writeState(_ s: MatterWorkspaceState) throws {
        try ensureRoot()
        try Data(jsonData(s)).write(to: stateURL, options: .atomic)
    }

    private func scan(dir: URL) -> [MatterLedgerEntry] {
        guard let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return subs.compactMap { sub in
            guard let data = try? Data(contentsOf: sub.appendingPathComponent("matter.json")),
                  let m = try? JSONDecoder().decode(Matter.self, from: data) else { return nil }
            return MatterLedgerEntry(from: m)
        }
    }

    private func regenerateLedger() throws {
        try ensureRoot()
        let s = state()
        let yaml = MatterLedgerYAML.render(enabled: s.enabled, active: s.activeSlug, entries: list())
        try Data(yaml.utf8).write(to: ledgerURL, options: .atomic)
    }

    private func ensureRoot() throws {
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    private func jsonData<T: Encodable>(_ v: T) -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(v)) ?? Data()
    }

    static func validateSlug(_ slug: String) throws {
        let bad = slug.isEmpty
            || slug.hasPrefix(".")
            || slug.contains("/") || slug.contains("\\")
            || slug != slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if bad { throw MatterStoreError.invalidSlug(slug) }
    }
}
