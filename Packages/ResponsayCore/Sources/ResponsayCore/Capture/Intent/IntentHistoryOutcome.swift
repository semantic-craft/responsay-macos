import Foundation

/// The coarse, content-free terminal disposition of an approved Intent-aware result, persisted to
/// History alongside the route (#565 / spec decision 29). Only approved finals reach persistence,
/// so this never carries `needsReview` / `safeUnavailable` — those states write no record. It
/// distinguishes a result written into the bound target (`inserted`) from one delivered to the
/// clipboard because there was no editable target or the target drifted (`copied`).
public enum IntentHistoryOutcome: String, Codable, Sendable, Equatable {
    case inserted
    case copied
}
