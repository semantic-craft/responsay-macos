import Foundation

/// 434 — the auto-learn flywheel. Turns the user's post-insertion edits into hotword
/// candidates by owning the cross-edit ``HotwordLearner`` state: the macOS layer feeds it
/// (inserted, userFinal) pairs detected via AX and persists the terms it promotes.
///
/// Pure value type — the toggle (`enabled`) and the already-known hotwords (`existingHotwords`)
/// are per-call inputs the caller reads from settings + the store, so this stays testable
/// without UserDefaults or the Keychain.
public struct HotwordAutoLearnCoordinator: Sendable {
    private var learner: HotwordLearner

    public init(promotionThreshold: Int = 2) {
        self.learner = HotwordLearner(promotionThreshold: promotionThreshold)
    }

    /// Observe one post-insertion edit; return any terms newly promoted to the store.
    public mutating func recordEdit(
        inserted: String,
        userFinal: String,
        enabled: Bool,
        existingHotwords: Set<String>
    ) -> [HotwordCandidate] {
        // Gate before observing: a disabled edit isn't even accumulated, so flipping the
        // toggle on later never back-fills from edits made while it was off.
        guard enabled else { return [] }
        let delta = EditDelta.compute(inserted: inserted, userFinal: userFinal)
        // Don't re-propose a term the store already knows (the user may have corrected a
        // mishearing of an existing hotword) — only surface genuinely new terms to add.
        return learner.observe(delta).filter { !existingHotwords.contains($0.term) }
    }
}
