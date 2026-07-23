import Foundation

/// Host category for a browser URL (issue 115). New enum, no conflict.
public enum URLHostCategory: String, Codable, Sendable, CaseIterable {
    case officialLawDatabase
    case commercialLegalDatabase
    case academicDatabase
    case documentEditor
    case emailOrMessage
    case searchEngine
    case unknown
}

/// A privacy-safe URL signal: **host + category only** (the full URL / query is
/// never emitted — coord. with 110). Boosts use built `LegalScene`; the source
/// hint uses the built `VerificationSourcePreference`.
public struct URLSignal: Codable, Sendable, Equatable {
    public let host: String?
    public let category: URLHostCategory
    public let legalSceneBoosts: [LegalScenePrior]
    public let verificationSourceHint: VerificationSourcePreference?

    public init(
        host: String?,
        category: URLHostCategory,
        legalSceneBoosts: [LegalScenePrior] = [],
        verificationSourceHint: VerificationSourcePreference? = nil
    ) {
        self.host = host
        self.category = category
        self.legalSceneBoosts = legalSceneBoosts
        self.verificationSourceHint = verificationSourceHint
    }
}

/// Classifies the browser URL already read by `CaptureGateContextReader` — does
/// not re-implement browser reading. v0 = host classification + search-entry
/// hints; no page scraping, no回填 (issue 115).
public struct BrowserURLClassifier: Sendable {
    public init() {}

    public func classify(_ urlString: String) -> URLSignal {
        let host = Self.host(from: urlString)
        guard let host else { return URLSignal(host: nil, category: .unknown) }

        for entry in Self.table where host == entry.host || host.hasSuffix("." + entry.host) {
            return URLSignal(host: host, category: entry.category,
                             legalSceneBoosts: entry.boosts, verificationSourceHint: entry.hint)
        }
        return URLSignal(host: host, category: .unknown)
    }

    /// Extract the lowercased host, dropping scheme / path / query (privacy).
    static func host(from urlString: String) -> String? {
        var string = urlString.trimmingCharacters(in: .whitespaces)
        if let range = string.range(of: "://") { string = String(string[range.upperBound...]) }
        if let slash = string.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            string = String(string[..<slash])
        }
        if let at = string.lastIndex(of: "@") { string = String(string[string.index(after: at)...]) }
        if let colon = string.firstIndex(of: ":") { string = String(string[..<colon]) }
        let host = string.lowercased()
        return host.isEmpty ? nil : host
    }

    private struct Entry {
        let host: String
        let category: URLHostCategory
        let boosts: [LegalScenePrior]
        let hint: VerificationSourcePreference?
    }

    private static let table: [Entry] = [
        Entry(host: "flk.npc.gov.cn", category: .officialLawDatabase,
              boosts: [LegalScenePrior(scene: .litigation, weight: 0.4, reason: "国家法律法规库")], hint: .govLaw),
        Entry(host: "court.gov.cn", category: .officialLawDatabase,
              boosts: [LegalScenePrior(scene: .litigation, weight: 0.4, reason: "裁判文书网")], hint: .govLaw),
        Entry(host: "pkulaw.com", category: .commercialLegalDatabase,
              boosts: [LegalScenePrior(scene: .litigation, weight: 0.3, reason: "北大法宝")], hint: .pkulaw),
        Entry(host: "cnki.net", category: .academicDatabase,
              boosts: [LegalScenePrior(scene: .academicWriting, weight: 0.4, reason: "知网")], hint: .cnki),
        Entry(host: "wanfangdata.com.cn", category: .academicDatabase,
              boosts: [LegalScenePrior(scene: .academicWriting, weight: 0.3, reason: "万方")], hint: .cnki),
        Entry(host: "xueshu.baidu.com", category: .academicDatabase,
              boosts: [LegalScenePrior(scene: .academicWriting, weight: 0.4, reason: "百度学术")], hint: .baiduScholar),
        Entry(host: "docs.google.com", category: .documentEditor, boosts: [], hint: nil),
        Entry(host: "notion.so", category: .documentEditor, boosts: [], hint: nil),
        Entry(host: "feishu.cn", category: .documentEditor, boosts: [], hint: nil),
        Entry(host: "mail.google.com", category: .emailOrMessage, boosts: [], hint: nil),
        Entry(host: "google.com", category: .searchEngine, boosts: [], hint: nil),
        Entry(host: "baidu.com", category: .searchEngine, boosts: [], hint: nil),
    ]
}
