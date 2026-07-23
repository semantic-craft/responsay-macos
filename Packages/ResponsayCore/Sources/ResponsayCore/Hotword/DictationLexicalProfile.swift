import CryptoKit
import Foundation

public enum LexicalProfilePrivacyRejectionReason: String, Sendable, Codable, Equatable, CaseIterable {
    case protectedApp
    case url
    case email
    case filePath
    case command
    case secretLike
    case codeLike
}

public struct LexicalProfilePrivacyGate: Sendable, Equatable {
    public init() {}

    public func rejectionReason(
        text: String?,
        appName: String? = nil,
        windowTitle: String? = nil
    ) -> LexicalProfilePrivacyRejectionReason? {
        if isProtectedApp(appName) { return .protectedApp }
        for value in [text, windowTitle].compactMap({ $0 }) {
            if matches(value, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, .caseInsensitive) { return .email }
            if hasURL(value) { return .url }
            if matches(value, #"(^|\s)(/Users/|/Volumes/|/tmp/|~/|\./|\.\./)"#) { return .filePath }
            if matches(value.trimmingCharacters(in: .whitespacesAndNewlines), #"^(sudo|git|curl|ssh|brew|npm|pnpm|yarn|python|node|rm|mv|cp|cd|ls|cat|chmod|chown)\b"#) { return .command }
            if hasCodeShape(value) { return .codeLike }
            if hasSecretShape(value) { return .secretLike }
        }
        return nil
    }

    public func rejectionReason(
        texts: [String?],
        appName: String? = nil,
        windowTitle: String? = nil
    ) -> LexicalProfilePrivacyRejectionReason? {
        if isProtectedApp(appName) { return .protectedApp }
        for text in texts {
            if let reason = rejectionReason(text: text, appName: nil, windowTitle: nil) { return reason }
        }
        return rejectionReason(text: windowTitle, appName: nil, windowTitle: nil)
    }

    private func isProtectedApp(_ appName: String?) -> Bool {
        let value = (appName ?? "").lowercased()
        return ["terminal", "iterm", "xcode", "com.apple.dt.xcode", "com.apple.terminal", "com.googlecode.iterm2"]
            .contains { value.contains($0) }
    }

    private func hasURL(_ value: String) -> Bool {
        matches(value, #"https?://|www\.|\b[a-z0-9.-]+\.(com|org|net|cn|edu|gov)(/|\b)"#, .caseInsensitive)
    }

    private func hasSecretShape(_ value: String) -> Bool {
        matches(value, #"sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,}|AKIA[0-9A-Z]{12,}|Bearer\s+[A-Za-z0-9._-]{12,}"#)
            || matches(value, #"(api[_-]?key|token|password|secret)\s*="#, .caseInsensitive)
    }

    private func hasCodeShape(_ value: String) -> Bool {
        matches(value, #"[{};]|==|=>|\b(func|class|struct|import|let|var|const|return)\b|[A-Za-z_][A-Za-z0-9_]*\([^)]*\)"#)
    }

    private func matches(_ value: String, _ pattern: String, _ options: String.CompareOptions = []) -> Bool {
        value.range(of: pattern, options: options.union(.regularExpression)) != nil
    }
}

public struct DictationLexicalProfile: Sendable, Codable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let refreshedAt: Date
    public let terms: [Term]
    public let aliases: [Alias]
    public let recentAcceptedCorrections: [Correction]
    public let sourceSummary: [String: Int]
    public let sceneSummary: [String: Int]
    public let privacyRejectionCounts: [String: Int]
    public let profileHash: String

    public struct Term: Sendable, Codable, Equatable {
        public let text: String
        public let source: String
        public let score: Double
        public let lastUsedAt: Date?
    }

    public struct Alias: Sendable, Codable, Equatable {
        public let sourceTerm: String
        public let term: String
        public let source: String
        public let lastUsedAt: Date?
    }

    public struct Correction: Sendable, Codable, Equatable {
        public let sourceTerm: String
        public let term: String
        public let source: String
        public let correctedAt: Date
    }

    public var markdownMirror: String {
        var lines = [
            "# Dictation Lexical Profile",
            "",
            "- schemaVersion: \(schemaVersion)",
            "- profileHash: \(profileHash)",
            "- terms: \(terms.count)",
            "- aliases: \(aliases.count)",
            "",
            "## Terms",
        ]
        lines += terms.map { "- \($0.text) [\($0.source)]" }
        lines += ["", "## Aliases"]
        lines += aliases.map { "- \($0.sourceTerm) -> \($0.term) [\($0.source)]" }
        lines += ["", "## Source Summary"]
        lines += sourceSummary.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        lines += ["", "## Privacy Rejections"]
        lines += privacyRejectionCounts.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct DictationLexicalProfileBuilder: Sendable {
    public static let maxTerms = 40
    public static let maxAliases = 32
    public static let maxRecentCorrections = 12

    private let gate: LexicalProfilePrivacyGate

    public init(gate: LexicalProfilePrivacyGate = LexicalProfilePrivacyGate()) {
        self.gate = gate
    }

    public func build(
        store: HotwordStore,
        records: [HotwordLearningRecord],
        now: Date = Date()
    ) -> DictationLexicalProfile {
        var terms: [DictationLexicalProfile.Term] = []
        var seenTerms = Set<String>()
        var aliases: [DictationLexicalProfile.Alias] = []
        var recent: [DictationLexicalProfile.Correction] = []
        var sourceSummary: [String: Int] = [:]
        var sceneSummary: [String: Int] = [:]
        var privacyCounts: [String: Int] = [:]

        func reject(_ reason: LexicalProfilePrivacyRejectionReason?) -> Bool {
            guard let reason else { return false }
            privacyCounts[reason.rawValue, default: 0] += 1
            return true
        }

        func addTerm(_ text: String, source: String, score: Double, lastUsedAt: Date?) {
            guard let value = clean(text), !seenTerms.contains(value) else { return }
            guard !reject(gate.rejectionReason(text: value)) else { return }
            seenTerms.insert(value)
            sourceSummary[source, default: 0] += 1
            terms.append(.init(text: value, source: source, score: score, lastUsedAt: lastUsedAt))
        }

        for entry in store.userTermEntries {
            addTerm(
                entry.text,
                source: entry.source.rawValue,
                score: entry.source == .manual ? 100 : 80 + ((entry.confidence ?? 0.8) * 10),
                lastUsedAt: entry.learnedAt)
        }

        let tombstoned = HotwordLearningHistory(records: records).tombstonedTerms()
        for record in records where record.status == .added && !tombstoned.contains(record.term) {
            if reject(gate.rejectionReason(
                texts: [record.term, record.sourceTerm],
                appName: record.appName,
                windowTitle: record.windowTitle)) { continue }

            addTerm(record.term, source: "recent", score: 70 + ((record.confidence ?? 0.7) * 10), lastUsedAt: record.learnedAt)
            if let app = clean(record.appName), !app.isEmpty {
                sceneSummary[app, default: 0] += 1
            }
            guard let source = clean(record.sourceTerm), !source.isEmpty, source != record.term else { continue }
            if aliases.count < Self.maxAliases {
                sourceSummary["alias", default: 0] += 1
                aliases.append(.init(
                    sourceTerm: source,
                    term: record.term,
                    source: record.source.rawValue,
                    lastUsedAt: record.learnedAt))
            }
            if recent.count < Self.maxRecentCorrections {
                recent.append(.init(
                    sourceTerm: source,
                    term: record.term,
                    source: record.source.rawValue,
                    correctedAt: record.learnedAt))
            }
        }

        let sortedTerms = Array(terms.sorted(by: sortTerms).prefix(Self.maxTerms))
        let profileHash = hash(terms: sortedTerms, aliases: aliases, recent: recent)
        return DictationLexicalProfile(
            schemaVersion: DictationLexicalProfile.schemaVersion,
            refreshedAt: now,
            terms: sortedTerms,
            aliases: aliases,
            recentAcceptedCorrections: recent,
            sourceSummary: sourceSummary,
            sceneSummary: sceneSummary,
            privacyRejectionCounts: privacyCounts,
            profileHash: profileHash)
    }

    private func sortTerms(_ lhs: DictationLexicalProfile.Term, _ rhs: DictationLexicalProfile.Term) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(HotwordStore.maxTermLength))
    }

    private func hash(
        terms: [DictationLexicalProfile.Term],
        aliases: [DictationLexicalProfile.Alias],
        recent: [DictationLexicalProfile.Correction]
    ) -> String {
        let payload = [
            terms.map { "\($0.text)|\($0.source)" }.joined(separator: "\n"),
            aliases.map { "\($0.sourceTerm)->\($0.term)" }.joined(separator: "\n"),
            recent.map { "\($0.sourceTerm)->\($0.term)" }.joined(separator: "\n"),
        ].joined(separator: "\n--\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
