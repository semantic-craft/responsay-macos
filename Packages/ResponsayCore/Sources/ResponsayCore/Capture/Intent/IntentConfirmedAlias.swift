import Foundation

/// A `surface → canonical` alias the user explicitly confirmed by picking a grounded entity
/// candidate in the review capsule (#565 / spec decisions 28, 49). The macOS learning sink feeds it
/// into the EXISTING dictionary + learned-alias ledger (provenance `.manual`, undo/tombstone
/// intact) — gated by the learning toggle and the sensitive-context privacy gate. Nothing else
/// (auto-adopted unique candidates, model reorder, side notes, grounding hints, unconfirmed names)
/// ever produces one of these.
public struct IntentConfirmedAlias: Sendable, Equatable {
    /// The original spoken/misheard span the confirmed candidate replaced.
    public let surface: String
    /// The canonical value the user confirmed as correct.
    public let canonical: String

    public init(surface: String, canonical: String) {
        self.surface = surface
        self.canonical = canonical
    }
}
