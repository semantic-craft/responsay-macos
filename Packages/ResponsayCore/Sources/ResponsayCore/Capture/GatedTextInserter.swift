import Foundation

/// Opaque per-capture session identifier (issue 087 item 9). Correlates logs and
/// scopes the one-time insert gate so a cloud failure + on-device fallback, or a
/// double-tap that slips past the phase machine, can't insert the same text twice.
public struct CaptureSessionID: Hashable, Sendable {
    public let value: UUID
    public init(value: UUID = UUID()) { self.value = value }
}

/// Wraps a `TextInserter` so each capture session inserts **at most once** — the
/// one-time insert gate from issue 087 item 9. Call `beginSession()` when a new
/// capture starts; every insert afterward is a no-op until the next session.
///
/// A *failed* insert does NOT consume the gate (so a genuine retry can still
/// land); only a successful insert closes it.
@MainActor
public final class GatedTextInserter: TextInserter {
    private let base: TextInserter
    public private(set) var sessionID = CaptureSessionID()
    public private(set) var hasInserted = false

    public init(_ base: TextInserter) {
        self.base = base
    }

    /// Open a fresh gate for a new capture session.
    public func beginSession(_ id: CaptureSessionID = CaptureSessionID()) {
        sessionID = id
        hasInserted = false
    }

    public func insert(_ text: String) async throws {
        guard !hasInserted else { return }
        hasInserted = true                 // claim synchronously (re-entrancy safe)
        do {
            try await base.insert(text)
        } catch {
            hasInserted = false            // a failed insert frees the gate for retry
            throw error
        }
    }
}
