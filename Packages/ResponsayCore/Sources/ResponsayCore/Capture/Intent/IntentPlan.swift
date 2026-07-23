import Foundation

public struct IntentPlan: Codable, Sendable, Equatable {
    public let version: Int
    public let decision: IntentPlanDecision
    public let units: [IntentPlanUnit]
    public let supersessions: [IntentSupersession]
    /// Selected entity candidate IDs (#562). Pure selection — the app owns each candidate's
    /// value and slot; the compiler can only point at pre-numbered table entries. Absent in the
    /// provider JSON ⇒ empty (older plans stay valid).
    public let entities: [String]
    /// Optional organization of the renderable units (#563). Absent ⇒ prose in plan order;
    /// present ⇒ deterministic paragraphs / bullets / steps over exactly the renderable IDs.
    public let structure: IntentPlanStructure?

    public init(
        version: Int,
        decision: IntentPlanDecision,
        units: [IntentPlanUnit],
        supersessions: [IntentSupersession],
        entities: [String] = [],
        structure: IntentPlanStructure? = nil
    ) {
        self.version = version
        self.decision = decision
        self.units = units
        self.supersessions = supersessions
        self.entities = entities
        self.structure = structure
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, decision, units, supersessions, entities, structure
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        decision = try container.decode(IntentPlanDecision.self, forKey: .decision)
        units = try container.decode([IntentPlanUnit].self, forKey: .units)
        supersessions = try container.decode([IntentSupersession].self, forKey: .supersessions)
        entities = try container.decodeIfPresent([String].self, forKey: .entities) ?? []
        structure = try container.decodeIfPresent(IntentPlanStructure.self, forKey: .structure)
    }
}
