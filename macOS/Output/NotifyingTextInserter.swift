import Foundation
import ResponsayCore

/// 434 — wraps the real `TextInserter` so the auto-learn controller can snapshot the focused
/// field right after Responsay inserts dictation text. Forwards `insert` unchanged, then fires
/// `onInsert` once the write returns. The callback is responsible for any settle-delay before
/// reading the field back (CGEvent insertion lands asynchronously).
final class NotifyingTextInserter: TextInserter, @unchecked Sendable {
    private let wrapped: TextInserter
    private let onInsert: @Sendable (String) -> Void

    init(wrapping wrapped: TextInserter, onInsert: @escaping @Sendable (String) -> Void) {
        self.wrapped = wrapped
        self.onInsert = onInsert
    }

    func insert(_ text: String) async throws {
        try await wrapped.insert(text)
        onInsert(text)
    }
}
