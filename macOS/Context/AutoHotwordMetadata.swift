import Foundation
import ResponsayCore

struct AutoHotwordMetadata: Codable, Equatable {
    let source: HotwordLearningSource
    let reason: String
    let learnedAt: Date
    /// Learn-confidence at the time the term was added (#466), retained for local learning
    /// history. `nil` = user-confirmed, or a legacy record persisted before #466.
    let confidence: Double?
    /// Scene-aware biasing (P0a): the `RegisterTier` rawValue of the app/site where this term was
    /// learned. Biasing suppresses it when the current app's tier differs (so legal terms don't bias
    /// chat dictation, etc.). `nil` = global — unclassified at learn time, or a record persisted
    /// before P0a (synthesized Codable decodes the missing key as nil, so old metadata stays valid).
    let scene: String?

    init(
        source: HotwordLearningSource,
        reason: String,
        learnedAt: Date,
        confidence: Double? = nil,
        scene: String? = nil
    ) {
        self.source = source
        self.reason = reason
        self.learnedAt = learnedAt
        self.confidence = confidence
        self.scene = scene
    }
}
