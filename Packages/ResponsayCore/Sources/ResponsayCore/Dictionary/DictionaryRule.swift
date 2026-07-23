import Foundation

/// Stable string id for a scene preset (e.g. `"legal"`, `"academic"`).
public typealias ScenePresetID = String

/// What kind of correction a `DictionaryRule` performs.
/// `hotword` is a *recognition-bias* term (it joins the ASR hotword list), not a
/// post-processing text edit — the engine skips it (issue 158/160).
public enum DictionaryRuleType: String, Codable, Sendable, Equatable, CaseIterable {
    case hotword
    case exactCorrection
    case wildcardCorrection
    case regexCorrection
}

/// Where a rule applies. Empty array = wildcard (applies regardless of that axis).
public struct DictionaryScope: Codable, Sendable, Equatable {
    public var languages: [String]
    public var scenes: [ScenePresetID]
    public var appBundleIDs: [String]

    public init(languages: [String] = [], scenes: [ScenePresetID] = [], appBundleIDs: [String] = []) {
        self.languages = languages
        self.scenes = scenes
        self.appBundleIDs = appBundleIDs
    }

    /// Applies to everything.
    public static let any = DictionaryScope()

    /// A restricted axis (non-empty list) requires the context to provide a
    /// matching value; an unrestricted axis (empty list) always passes.
    public func matches(_ context: DictionaryContext) -> Bool {
        func ok(_ allowed: [String], _ value: String?) -> Bool {
            allowed.isEmpty || (value.map(allowed.contains) ?? false)
        }
        return ok(languages, context.language)
            && ok(scenes, context.scene)
            && ok(appBundleIDs, context.appBundleID)
    }
}

/// A user dictionary / hotword / correction rule (spec §7.2.1). Mutable value
/// type — `hitCount` accrues over runs, `enabled` is a UI toggle.
public struct DictionaryRule: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var pattern: String
    public var replacement: String
    public var ruleType: DictionaryRuleType
    public var scope: DictionaryScope
    public var enabled: Bool
    public var hitCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        pattern: String,
        replacement: String,
        ruleType: DictionaryRuleType = .exactCorrection,
        scope: DictionaryScope = .any,
        enabled: Bool = true,
        hitCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.ruleType = ruleType
        self.scope = scope
        self.enabled = enabled
        self.hitCount = hitCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, pattern, replacement, ruleType, scope, enabled, hitCount, createdAt, updatedAt
    }

    /// Tolerant decode: only `pattern`/`replacement` are required; everything
    /// else defaults so a minimal authored rule still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pattern = try c.decode(String.self, forKey: .pattern)
        replacement = try c.decode(String.self, forKey: .replacement)
        ruleType = try c.decodeIfPresent(DictionaryRuleType.self, forKey: .ruleType) ?? .exactCorrection
        scope = try c.decodeIfPresent(DictionaryScope.self, forKey: .scope) ?? .any
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        hitCount = try c.decodeIfPresent(Int.self, forKey: .hitCount) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
