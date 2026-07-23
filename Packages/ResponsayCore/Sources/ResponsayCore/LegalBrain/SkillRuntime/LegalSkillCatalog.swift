import Foundation

// MARK: - Phase 2 (#400) — GitHub read-only legal-skill catalog
//
// A public GitHub repo hosts `index.json` listing community `*.LEGAL_SKILL.md` files; the app
// browses it and installs via the existing `LegalSkillImporter` (same dedup / consent / [待核] /
// privacy path). No server, no publish — curation = PRs to the catalog repo. Pure given an
// injected fetcher, so it unit-tests without the network.

/// One entry in the catalog `index.json`.
public struct LegalSkillCatalogEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    public let domain: String?
    public let tags: [String]
    public let author: String?
    public let version: String?
    public let kind: String?
    /// Absolute URL of the `*.LEGAL_SKILL.md` source (e.g. a raw.githubusercontent.com link).
    public let rawURL: String

    public init(
        id: String, title: String, description: String? = nil, domain: String? = nil,
        tags: [String] = [], author: String? = nil, version: String? = nil,
        kind: String? = nil, rawURL: String
    ) {
        self.id = id; self.title = title; self.description = description; self.domain = domain
        self.tags = tags; self.author = author; self.version = version; self.kind = kind
        self.rawURL = rawURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, domain, tags, author, version, kind, rawURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(String.self, forKey: .author)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        rawURL = try c.decode(String.self, forKey: .rawURL)
    }

    /// Install state vs what's already imported. Key absent → not installed; present with a
    /// stored version → compare; present without a version → treated as installed (can't tell).
    public func installState(installedVersions: [String: String?]) -> LegalSkillCatalogInstallState {
        guard let inner = installedVersions[id] else { return .notInstalled }
        guard let catalogV = version, let installedV = inner else { return .installed }
        return LegalSkillVersion.compare(catalogV, installedV) == .orderedDescending
            ? .updateAvailable : .installed
    }
}

public struct LegalSkillCatalogIndex: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let skills: [LegalSkillCatalogEntry]

    public init(schemaVersion: Int = 1, skills: [LegalSkillCatalogEntry]) {
        self.schemaVersion = schemaVersion
        self.skills = skills
    }
}

public enum LegalSkillCatalogInstallState: Equatable, Sendable {
    case notInstalled
    case installed
    case updateAvailable
}

public enum LegalSkillCatalogError: Error, Equatable {
    case badRawURL(String)
    case notUTF8
}

public struct LegalSkillCatalogClient: Sendable {
    public typealias Fetcher = @Sendable (URL) async throws -> Data

    /// Default catalog index. Overridable via the `legal.catalog.indexURL` UserDefaults key (dev).
    public static let defaultIndexURLString =
        "https://raw.githubusercontent.com/semantic-craft/responsay-legal-skills/main/index.json"

    private let indexURL: URL
    private let fetch: Fetcher

    public init(indexURL: URL, fetch: @escaping Fetcher) {
        self.indexURL = indexURL
        self.fetch = fetch
    }

    /// Production client: URLSession fetcher + the default (or dev-overridden) index URL.
    public static func live(defaults: UserDefaults = .standard) -> LegalSkillCatalogClient {
        let urlString = defaults.string(forKey: "legal.catalog.indexURL") ?? defaultIndexURLString
        let url = URL(string: urlString) ?? URL(string: defaultIndexURLString)!
        return LegalSkillCatalogClient(indexURL: url) { url in
            try await URLSession.shared.data(from: url).0
        }
    }

    public func loadIndex() async throws -> LegalSkillCatalogIndex {
        let data = try await fetch(indexURL)
        return try JSONDecoder().decode(LegalSkillCatalogIndex.self, from: data)
    }

    public func downloadSkillMarkdown(_ entry: LegalSkillCatalogEntry) async throws -> String {
        // Require a real absolute URL (scheme + host). The system URL parser is lenient enough
        // to accept bare junk, so check the parts a fetch actually needs.
        let trimmed = entry.rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            throw LegalSkillCatalogError.badRawURL(entry.rawURL)
        }
        let data = try await fetch(url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw LegalSkillCatalogError.notUTF8
        }
        return markdown
    }
}

public enum LegalSkillVersion {
    /// Numeric-aware compare of dotted version strings ("1.2" < "1.10"). Non-numeric components
    /// fall back to lexicographic; missing trailing components count as 0.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map(String.init)
        let pb = b.split(separator: ".").map(String.init)
        for i in 0..<max(pa.count, pb.count) {
            let xa = i < pa.count ? pa[i] : "0"
            let xb = i < pb.count ? pb[i] : "0"
            if let na = Int(xa), let nb = Int(xb) {
                if na != nb { return na < nb ? .orderedAscending : .orderedDescending }
            } else if xa != xb {
                return xa < xb ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
