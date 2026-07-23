import Foundation

/// A term the flywheel proposes auto-adding to the hotword store (✦自动添加).
public struct HotwordCandidate: Sendable, Equatable {
    public let term: String
    public let occurrences: Int

    public init(term: String, occurrences: Int) {
        self.term = term
        self.occurrences = occurrences
    }
}

/// Accumulates the user's post-insertion term fixes and promotes the ones that
/// recur into auto-add candidates (issue 053 judgment brain). Pure value type —
/// the macOS layer feeds it ``EditDelta``s and persists/merges the candidates.
public struct HotwordLearner: Sendable {
    private let promotionThreshold: Int
    private let minTermLength: Int
    private let maxTermLength: Int
    private var counts: [Substitution: Int] = [:]
    private var promoted: Set<String> = []

    public init(promotionThreshold: Int = 2, minTermLength: Int = 2, maxTermLength: Int = 40) {
        self.promotionThreshold = max(1, promotionThreshold)
        self.minTermLength = minTermLength
        self.maxTermLength = maxTermLength
    }

    /// Record one edit; return any terms newly crossing the promotion threshold.
    public mutating func observe(_ delta: EditDelta) -> [HotwordCandidate] {
        // A large rewrite is a transcription-quality signal, not a term to learn.
        guard !delta.isLargeModify else { return [] }

        var newlyPromoted: [HotwordCandidate] = []
        for substitution in delta.substitutions where isLearnable(substitution.to) {
            let key = Substitution(from: substitution.from, to: substitution.to)
            let count = (counts[key] ?? 0) + 1
            counts[key] = count
            if count >= promotionThreshold, !promoted.contains(substitution.to) {
                promoted.insert(substitution.to)
                newlyPromoted.append(HotwordCandidate(term: substitution.to, occurrences: count))
            }
        }
        return newlyPromoted
    }

    /// Term-like = not a lone particle, not a whole phrase.
    private func isLearnable(_ term: String) -> Bool {
        let length = term.count
        return length >= minTermLength && length <= maxTermLength
    }

    private struct Substitution: Hashable {
        let from: String
        let to: String
    }
}
