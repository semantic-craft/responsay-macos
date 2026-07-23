import Foundation

public enum IntentReviewReason: String, Sendable, Equatable {
    /// The compiler itself returned `needsReview` (e.g. a correction with no unique referent).
    case compilerRequested
    /// Preflight veto (#561, spec decision 22): the raw utterance contains an obvious spoken
    /// correction cue that the verified plan did not classify as control speech.
    case unexplainedCorrectionCue
    /// Preflight veto: an obvious side-note directive the plan left as renderable content.
    case unexplainedSideNoteCue
    /// Preflight veto (#562): the utterance contains obvious 口述释字 clue units the plan did
    /// not classify as grounding — the clue would leak into the draft as prose.
    case unexplainedGroundingCue
    /// #562: the selected entity candidate sits on a contested slot (another whitelisted
    /// candidate proves a different spelling for the same span) — the user picks in review.
    case ambiguousEntityCandidates
}
