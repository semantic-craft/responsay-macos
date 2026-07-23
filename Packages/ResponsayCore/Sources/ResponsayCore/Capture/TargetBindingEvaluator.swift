import Foundation

/// Decides — from the capture-start snapshot and a fresh pre-commit snapshot — whether a verified
/// result may still be inserted into its bound target, or must fall back to a safe copy (#560).
/// Pure and host-agnostic: the macOS host reads the snapshots via Accessibility, this decides.
///
/// It keys the decision on the *reliable* identity signals — the frontmost app's bundle id and
/// process, the focused window, and whether the target can take text. A field that is `nil` on
/// both sides (e.g. an unreadable window title) is not treated as drift, so ordinary dictation
/// into a stable field isn't needlessly downgraded to a copy; a field that is present and differs
/// is drift. Finer selection-level drift is a real-host refinement left to #568.
enum TargetBindingEvaluator {
    static func decide(
        start: InsertionTargetSnapshot?,
        current: InsertionTargetSnapshot?
    ) -> InsertionCommitDecision {
        // No identifiable target at capture start → there was nothing to bind to; never guess a
        // target that only appeared later.
        guard let start, start.bundleID != nil else { return .safeCopy(.identityUnknown) }
        guard let current, current.bundleID != nil else { return .safeCopy(.targetVanished) }

        guard current.bundleID == start.bundleID else { return .safeCopy(.appChanged) }
        // A relaunch reuses the bundle id under a new pid — that's a different instance.
        if let startPID = start.processID, let currentPID = current.processID, startPID != currentPID {
            return .safeCopy(.appChanged)
        }
        // Window/scene drift within the same app, only when both titles are known and differ.
        if let startWindow = start.windowTitle, let currentWindow = current.windowTitle,
           startWindow != currentWindow {
            return .safeCopy(.windowChanged)
        }
        guard current.isEditable else { return .safeCopy(.targetNotEditable) }
        return .insert
    }
}
