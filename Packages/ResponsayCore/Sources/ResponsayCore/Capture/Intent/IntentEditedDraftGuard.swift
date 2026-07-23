import Foundation

/// Re-verifies a *user-edited* sanitized draft before it may be inserted. A free edit has no plan
/// to run through `IntentPlanVerifier`, so this is the guard-level safety re-check that spec
/// decision #20 assigns to the post-render guard for plan-less text: the edit must be non-empty
/// and must not reintroduce any forbidden fragment (a correction cue or a superseded loser).
///
/// It is a conservative, fail-closed subset — there is no protected-literal extractor yet
/// (#561+), so this proves only "no control/abandoned span leaked back in" and "not empty".
/// Rejection keeps the capture in review (never a bypass insert), which is the safe direction.
enum IntentEditedDraftGuard {
    static func accepts(editedDraft: String, forbiddenFragments: [String]) -> Bool {
        guard !editedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        for fragment in forbiddenFragments where !fragment.isEmpty {
            if editedDraft.contains(fragment) { return false }
        }
        return true
    }
}
