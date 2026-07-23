import Foundation

public struct IntentPlanUnit: Codable, Sendable, Equatable {
    public let source: IntentPlanSourceReference
    public let role: IntentSourceRole

    public init(source: IntentPlanSourceReference, role: IntentSourceRole) {
        self.source = source
        self.role = role
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case source, role }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(IntentPlanSourceReference.self, forKey: .source)
        role = try container.decode(IntentSourceRole.self, forKey: .role)
    }
}
