import Foundation

/// The domain buckets a hotword can belong to. The store covers all six so the
/// dictionary spans the user's research-and-code vocabulary (issue 054 / ADR-0011).
public enum HotwordCategory: String, CaseIterable, Sendable, Codable {
    case legal
    case academic
    case code
    case citation
    case author
    case paperTitle
}

/// How a user term entered the dictionary: typed by the user (🖋手动添加) or grown
/// by the edit-tracking flywheel (✦自动添加, issue 053). Powers the 词典 UI filter.
public enum HotwordSource: String, Sendable, Codable, Equatable, CaseIterable {
    case manual
    case auto
}

/// A user dictionary term plus its provenance.
public struct HotwordTerm: Sendable, Equatable, Codable {
    public let text: String
    public let source: HotwordSource
    public let learnedSource: HotwordLearningSource?
    public let learnedAt: Date?
    /// Learn-confidence captured for auto-added terms and retained in local history.
    /// `nil` = manual, user-confirmed, or a legacy pre-#466 record.
    public let confidence: Double?

    public init(
        text: String,
        source: HotwordSource = .manual,
        learnedSource: HotwordLearningSource? = nil,
        learnedAt: Date? = nil,
        confidence: Double? = nil
    ) {
        self.text = text
        self.source = source
        self.learnedSource = learnedSource
        self.learnedAt = learnedAt
        self.confidence = confidence
    }
}

/// The app-side categorized hotword dictionary: seed defaults plus the user's own terms,
/// flattened into the `[String]` hint list sent with each ASR request (see ADR-0011).
/// Pure value type — this type only assembles the dictionary. Hard-match enforcement
/// (near-miss substitution) is `HotwordHardMatch.enforce`, the app-side Swift port of the
/// deleted Node backend's pass (ADR-0029), applied at `RoutedSpeechCaptureService.stop()`.
public struct HotwordStore: Sendable, Equatable {
    public static let maxTerms = 40
    public static let maxTermLength = 80

    /// User terms with provenance. `userTerms` is the flat text view used downstream.
    public let userTermEntries: [HotwordTerm]
    public let seeds: [HotwordCategory: [String]]

    public var userTerms: [String] { userTermEntries.map(\.text) }

    public init(
        userTerms: [String] = [],
        seeds: [HotwordCategory: [String]] = HotwordStore.defaultSeeds
    ) {
        self.userTermEntries = userTerms.map { HotwordTerm(text: $0, source: .manual) }
        self.seeds = seeds
    }

    public init(
        userTermEntries: [HotwordTerm],
        seeds: [HotwordCategory: [String]] = HotwordStore.defaultSeeds
    ) {
        self.userTermEntries = userTermEntries
        self.seeds = seeds
    }

    /// User entries of one provenance — for the 词典 UI's ✦/🖋 filter.
    public func userTermEntries(source: HotwordSource) -> [HotwordTerm] {
        userTermEntries.filter { $0.source == source }
    }

    /// Add flywheel-promoted terms as `.auto` entries, skipping any term already
    /// present (manual wins; never demote a manual term to auto).
    public func merging(autoAdded terms: [String]) -> HotwordStore {
        let existing = Set(userTermEntries.map(\.text))
        let additions = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !existing.contains($0) }
            .map { HotwordTerm(text: $0, source: .auto) }
        return HotwordStore(userTermEntries: userTermEntries + additions, seeds: seeds)
    }

    /// Seed terms for one category (empty for the user-driven buckets like author / paperTitle).
    public func terms(in category: HotwordCategory) -> [String] {
        seeds[category] ?? []
    }

    /// User terms first — so an explicitly added term survives the cap — then seeds in
    /// category order. Trimmed, length-capped, de-duplicated, limited to `limit`.
    public func flattened(limit: Int = HotwordStore.maxTerms) -> [String] {
        var ordered = userTerms
        for category in HotwordCategory.allCases {
            ordered.append(contentsOf: seeds[category] ?? [])
        }
        return HotwordStore.clean(ordered, limit: limit)
    }

    /// The same flattened dictionary, partitioned by provenance for the hard-match gate (#470):
    /// `user` = the user's typed + auto-learned terms (eligible for phonetic snap), `seed` = the
    /// generic seeds (exact-only). User-first ordering, the shared cap, and dedup are preserved —
    /// a term that is both keeps user provenance (it is cleaned first, so the seed copy drops).
    public func flattenedByProvenance(limit: Int = HotwordStore.maxTerms) -> (user: [String], seed: [String]) {
        let userSet = Set(HotwordStore.clean(userTerms, limit: limit))
        var user: [String] = []
        var seed: [String] = []
        for term in flattened(limit: limit) {
            if userSet.contains(term) { user.append(term) } else { seed.append(term) }
        }
        return (user, seed)
    }

    /// Starter terms we can verify generically. Author and paper-title are intentionally
    /// user-driven (no generic seed), but remain first-class categories.
    ///
    /// Product note (2026-06-29): the app NO LONGER seeds these into user dictionaries — it ships
    /// with no default hotwords. This list is retained only as (a) the value-type's default fixture
    /// and (b) the strip-list `ContextHotwordSettings.removeSeededDefaultsIfNeeded` uses to clean
    /// legacy installs that already had them folded in.
    public static let defaultSeeds: [HotwordCategory: [String]] = [
        .legal: ["CLSCI", "SSRN", "Westlaw"],
        .academic: ["arXiv", "DOI", "ORCID"],
        .code: ["Swift", "SwiftUI", "Xcode", "AVAudioEngine", "AudioKit"],
        .citation: ["BibTeX", "et al.", "ibid."],
        .author: [],
        .paperTitle: [],
    ]

    static func clean(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var output = [String]()
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let capped = String(trimmed.prefix(maxTermLength))
            guard !seen.contains(capped) else { continue }
            seen.insert(capped)
            output.append(capped)
            if output.count == limit { break }
        }
        return output
    }
}
