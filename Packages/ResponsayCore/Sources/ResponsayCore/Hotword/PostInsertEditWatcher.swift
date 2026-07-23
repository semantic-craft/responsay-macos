import Foundation

/// 434 — detects when the user edits text Responsay just inserted, so the auto-learn flywheel
/// can learn the correction. After an insertion the macOS layer snapshots the focused field
/// (``noteInsertion``); before the next capture it re-reads the same field (``observeEdit``).
/// If the user changed what we inserted, the (inserted, userFinal) pair flows to
/// ``HotwordAutoLearnCoordinator``.
///
/// Pure value type — the AX field reads are the caller's job, so the detection logic stays
/// testable without Accessibility. Diffing the WHOLE field value before vs after means the
/// caller never has to isolate the inserted region: `EditDelta`'s LCS naturally finds the
/// changed tokens, and an unrelated big edit trips its large-modify guard upstream.
public struct PostInsertEditWatcher: Sendable {
    private var pending: (text: String, app: String, sceneID: String?)?

    public init() {}

    /// Snapshot the field right after Responsay inserted into it.
    public mutating func noteInsertion(fieldText: String, app: String) {
        noteInsertion(fieldText: fieldText, app: app, sceneID: nil)
    }

    public mutating func noteInsertion(fieldText: String, app: String, sceneID: String? = nil) {
        pending = (text: fieldText, app: app, sceneID: sceneID)
    }

    /// Re-read the field; return the (inserted, userFinal) pair only when the user made a real
    /// correction (a from→to word replacement that isn't a wholesale rewrite). Benign changes
    /// (append / deletion / transient large edit) keep the window open; focus loss or a
    /// different field/app gives up. The snapshot is consumed only on a fire or a give-up.
    public mutating func observeEdit(fieldText: String?, app: String?) -> (inserted: String, userFinal: String)? {
        observeEdit(fieldText: fieldText, app: app, sceneID: nil)
    }

    public mutating func observeEdit(
        fieldText: String?,
        app: String?,
        sceneID: String? = nil
    ) -> (inserted: String, userFinal: String)? {
        guard let pending, let fieldText, let app else {
            self.pending = nil
            return nil
        }
        // Focus moved to a different field / window / app → don't cross-attribute; give up.
        guard app == pending.app, sceneID == pending.sceneID else {
            self.pending = nil
            return nil
        }
        // No change yet → keep observing (the window stays open).
        guard fieldText != pending.text else { return nil }

        // 444 — only a genuine word replacement (a from→to substitution that isn't a
        // wholesale rewrite) is a correction worth learning. Anything else KEEPS the window
        // OPEN rather than consuming it: a pure append (still typing), a pure deletion, or a
        // transient large edit (the user deleted the wrong term and hasn't retyped it yet).
        // So a real correction landing a poll later is still caught, instead of the first
        // benign keystroke ending the window.
        let delta = EditDelta.compute(inserted: pending.text, userFinal: fieldText)
        // A correction edits a term INSIDE what we inserted, so most of the inserted
        // text survives. When it has largely vanished, the field was submitted / cleared
        // / navigated, or we're re-reading a TUI's own chrome — e.g. a terminal sitting on
        // "Claude Code …" after Enter during a long rebuild. That's not a correction:
        // keep the window open (a real delayed edit can still land) but never learn from it.
        guard delta.insertedRetainedRatio >= 0.5 else { return nil }
        guard !delta.isLargeModify, !delta.substitutions.isEmpty else { return nil }

        self.pending = nil
        return (inserted: pending.text, userFinal: fieldText)
    }
}
