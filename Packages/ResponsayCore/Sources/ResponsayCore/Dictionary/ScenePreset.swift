import Foundation

/// A named bundle of rules + hotwords the user can toggle on as a group
/// (法条 / 案由 / 学术缩写…). Multi-select batch apply lives in the UI (issue 159);
/// this is the data structure (spec §7.2.1).
public struct ScenePreset: Codable, Identifiable, Sendable, Equatable {
    public var id: ScenePresetID
    public var name: String
    public var rules: [UUID]
    public var hotwords: [String]
    public var enabled: Bool

    public init(
        id: ScenePresetID,
        name: String,
        rules: [UUID] = [],
        hotwords: [String] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rules = rules
        self.hotwords = hotwords
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rules, hotwords, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ScenePresetID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        rules = try c.decodeIfPresent([UUID].self, forKey: .rules) ?? []
        hotwords = try c.decodeIfPresent([String].self, forKey: .hotwords) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}
