import Foundation

/// Optional structural organization for a render plan (#563, spec decisions 17/18). Absence
/// means PROSE — rendered units joined in plan order — so ordinary speech is never formatted
/// just to look "organized". When present, `groups` partitions the renderable source IDs:
/// every renderable unit appears exactly once (conservation is the hard boundary), and the
/// deterministic renderer alone turns groups into paragraphs, bullets or numbered steps. The
/// compiler can only arrange verified units; it cannot add headings, conclusions, greetings or
/// any other text through this field.
public struct IntentPlanStructure: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case paragraphs
        case bulletList
        case numberedSteps
    }

    public let kind: Kind
    /// Renderable source-unit IDs, grouped in output order: one group = one paragraph, bullet
    /// or step. Requires at least two groups — a one-group structure IS prose and must be
    /// expressed by omitting `structure` instead.
    public let groups: [[String]]

    public init(kind: Kind, groups: [[String]]) {
        self.kind = kind
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, groups }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        groups = try container.decode([[String]].self, forKey: .groups)
    }
}
