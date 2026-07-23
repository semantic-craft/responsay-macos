import Foundation

public struct IntentSupersession: Codable, Sendable, Equatable {
    public let winner: IntentPlanSourceReference
    public let loser: IntentPlanSourceReference
    public let cue: IntentPlanSourceReference

    public init(
        winner: IntentPlanSourceReference,
        loser: IntentPlanSourceReference,
        cue: IntentPlanSourceReference
    ) {
        self.winner = winner
        self.loser = loser
        self.cue = cue
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case winner, loser, cue }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        winner = try container.decode(IntentPlanSourceReference.self, forKey: .winner)
        loser = try container.decode(IntentPlanSourceReference.self, forKey: .loser)
        cue = try container.decode(IntentPlanSourceReference.self, forKey: .cue)
    }
}
