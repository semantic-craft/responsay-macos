import Foundation
import OSLog

/// Owns the read-aloud request identity and the stale-callback guard: every async step (synth,
/// anchor, highlight tick) validates it is still the live request before mutating controller state,
/// so a superseded read can't resurrect old playback. Extracted from ReadAloudController (07-05),
/// behaviour-preserving — the controller keeps a read-only `currentTransaction` forwarder and a thin
/// `isCurrent(_:phase:)` forwarder so its call sites are unchanged.
@MainActor
final class ReadAloudTransactionManager {
    private(set) var current: ReadAloudTransaction?
    private let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloud")

    func begin() -> ReadAloudTransaction {
        let tx = ReadAloudTransaction()
        current = tx
        return tx
    }

    func clear() {
        current = nil
    }

    func isCurrent(_ tx: ReadAloudTransaction, phase: String) -> Bool {
        guard current == tx else {
            Diag.tts(.info, "staleCallbackIgnored", fields: [
                "callbackPhase": phase,
                "oldRequestID": tx.requestID.uuidString,
                "currentRequestID": current?.requestID.uuidString ?? "none",
            ])
            log.notice("stale callback ignored phase=\(phase, privacy: .public) oldRequestID=\(tx.requestID.uuidString, privacy: .public) currentRequestID=\(self.current?.requestID.uuidString ?? "none", privacy: .public)")
            return false
        }
        return true
    }
}
