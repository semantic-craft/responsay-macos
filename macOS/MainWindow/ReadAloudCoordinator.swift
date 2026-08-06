import Foundation

/// Anything that speaks and can be told to stop — the single-flight participant.
@MainActor
protocol ReadAloudStoppable: AnyObject {
    func stop()
}

/// Cross-surface single-flight for read-aloud (issue 481). The Coach card, the
/// 任意提问 / Voice Assistant panel, and the selection menu each own their own
/// `ReadAloudController`; the reader window owns a `ReadAloudDocumentReader`. Before this,
/// starting a read on one surface left another surface's audio still playing. This holds a
/// single weak `active` reader and stops the previous one whenever a new read begins, so only
/// one surface ever speaks.
///
/// Per-request cancellation (`requestID`/`traceID`, P0-12) already guards a surface's
/// own restarts; this lifts "cancel the previous read" from per-surface to global.
@MainActor
final class ReadAloudCoordinator {
    static let shared = ReadAloudCoordinator()

    private weak var active: (any ReadAloudStoppable)?

    /// Make `reader` the sole active reader, stopping whoever was active before
    /// (a different instance). Idempotent for the same reader.
    func activate(_ reader: any ReadAloudStoppable) {
        if let active, active !== reader {
            active.stop()
        }
        active = reader
    }

    /// Clear `reader` from the active slot if it currently holds it.
    func resign(_ reader: any ReadAloudStoppable) {
        if active === reader { active = nil }
    }
}
