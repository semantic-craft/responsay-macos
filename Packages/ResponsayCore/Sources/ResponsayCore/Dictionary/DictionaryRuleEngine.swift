import Foundation

/// Runtime context used to decide which rules apply (scope filter).
public struct DictionaryContext: Sendable, Equatable {
    public var language: String?
    public var scene: ScenePresetID?
    public var appBundleID: String?

    public init(language: String? = nil, scene: ScenePresetID? = nil, appBundleID: String? = nil) {
        self.language = language
        self.scene = scene
        self.appBundleID = appBundleID
    }
}

/// One applied substitution — the unit of hit counting and audit.
public struct DictionaryEdit: Sendable, Equatable {
    public let ruleID: UUID
    public let before: String
    public let after: String

    public init(ruleID: UUID, before: String, after: String) {
        self.ruleID = ruleID
        self.before = before
        self.after = after
    }
}

/// Outcome of applying the dictionary to a transcript.
public struct DictionaryApplyResult: Sendable, Equatable {
    public let corrected: String
    public let edits: [DictionaryEdit]

    public init(corrected: String, edits: [DictionaryEdit]) {
        self.corrected = corrected
        self.edits = edits
    }

    public var totalHits: Int { edits.count }

    public func hitCount(for ruleID: UUID) -> Int {
        edits.reduce(0) { $0 + ($1.ruleID == ruleID ? 1 : 0) }
    }

    /// Rules that fired at least once, in first-fire order.
    public var firedRuleIDs: [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for edit in edits where !seen.contains(edit.ruleID) {
            seen.insert(edit.ruleID)
            ordered.append(edit.ruleID)
        }
        return ordered
    }

    /// Return `rules` with `hitCount` bumped by this run's hits (and `updatedAt`
    /// set to `now` for any rule that fired). Pure — caller persists the result.
    public func applyingHits(to rules: [DictionaryRule], at now: Date) -> [DictionaryRule] {
        rules.map { rule in
            let hits = hitCount(for: rule.id)
            guard hits > 0 else { return rule }
            var updated = rule
            updated.hitCount += hits
            updated.updatedAt = now
            return updated
        }
    }
}

/// Applies dictionary correction rules to a **final** ASR transcript (never
/// partials — issue 160). `hotword` rules are recognition bias, not edits, so
/// they are skipped here. Rolling back a false hit = disabling the offending
/// rule and re-applying (deterministic; the `enabled` flag is the lever).
public struct DictionaryRuleEngine: Sendable {
    public init() {}

    public func apply(
        to text: String,
        rules: [DictionaryRule],
        context: DictionaryContext = DictionaryContext()
    ) -> DictionaryApplyResult {
        var current = text
        var edits: [DictionaryEdit] = []
        for rule in rules where rule.enabled && rule.scope.matches(context) {
            let (next, ruleEdits): (String, [DictionaryEdit])
            switch rule.ruleType {
            case .hotword:
                continue
            case .exactCorrection:
                (next, ruleEdits) = Self.applyExact(rule, to: current)
            case .wildcardCorrection:
                (next, ruleEdits) = Self.applyWildcard(rule, to: current)
            case .regexCorrection:
                (next, ruleEdits) = Self.applyRegex(rule, to: current)
            }
            current = next
            edits.append(contentsOf: ruleEdits)
        }
        return DictionaryApplyResult(corrected: current, edits: edits)
    }

    // MARK: - Per-type application

    private static func applyExact(_ rule: DictionaryRule, to text: String) -> (String, [DictionaryEdit]) {
        guard !rule.pattern.isEmpty, rule.pattern != rule.replacement else { return (text, []) }
        var result = ""
        var edits: [DictionaryEdit] = []
        var index = text.startIndex
        while let range = text.range(of: rule.pattern, range: index..<text.endIndex) {
            result += text[index..<range.lowerBound]
            result += rule.replacement
            edits.append(DictionaryEdit(ruleID: rule.id, before: rule.pattern, after: rule.replacement))
            index = range.upperBound
        }
        result += text[index..<text.endIndex]
        return (result, edits)
    }

    private static func applyWildcard(_ rule: DictionaryRule, to text: String) -> (String, [DictionaryEdit]) {
        guard let pattern = WildcardPattern(pattern: rule.pattern) else { return (text, []) }
        return applyRegexLike(ruleID: rule.id, regex: pattern.regex, to: text) { match, ns in
            pattern.expand(replacement: rule.replacement, match: match, in: text)
        }
    }

    private static func applyRegex(_ rule: DictionaryRule, to text: String) -> (String, [DictionaryEdit]) {
        guard !rule.pattern.isEmpty, let regex = try? NSRegularExpression(pattern: rule.pattern) else {
            return (text, [])
        }
        return applyRegexLike(ruleID: rule.id, regex: regex, to: text) { match, _ in
            regex.replacementString(for: match, in: text, offset: 0, template: rule.replacement)
        }
    }

    /// Shared non-overlapping left-to-right replacement loop. `transform` builds
    /// the replacement for one match; edits are recorded only when text changes.
    private static func applyRegexLike(
        ruleID: UUID,
        regex: NSRegularExpression,
        to text: String,
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> (String, [DictionaryEdit]) {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }
        var result = ""
        var edits: [DictionaryEdit] = []
        var cursor = 0
        for match in matches {
            let before = ns.substring(with: match.range)
            let after = transform(match, ns)
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += after
            cursor = match.range.location + match.range.length
            if before != after {
                edits.append(DictionaryEdit(ruleID: ruleID, before: before, after: after))
            }
        }
        result += ns.substring(from: cursor)
        return (result, edits)
    }
}
