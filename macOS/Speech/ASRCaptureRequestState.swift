import Foundation

typealias ASRKeyReader = @Sendable (String) -> String?

final class CaptureUserDefaults: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}

/// Per-router capture snapshot for the terms an adapter actually placed in its request. Providers
/// resolve hints at different times (Qwen during async preparation, batch HTTP at stop), so the
/// finalizer must reuse the concrete request value instead of mutable settings or screen state.
final class CaptureRequestEchoTerms: @unchecked Sendable {
    private let lock = NSLock()
    private var frozen: [String]?

    func reset() {
        lock.withLock { frozen = nil }
    }

    @discardableResult
    func freeze(_ terms: [String]) -> [String] {
        lock.withLock {
            if let frozen { return frozen }
            frozen = terms
            return terms
        }
    }

    func replace(_ terms: [String]) {
        lock.withLock { frozen = terms }
    }

    var value: [String]? { lock.withLock { frozen } }
}
