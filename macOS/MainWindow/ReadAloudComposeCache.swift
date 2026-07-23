import Foundation
import ResponsayCore

/// In-memory cache of composed read-aloud audio (issue 495), so re-reading the same Coach
/// standard sentence skips re-synthesis. Keyed by text + engine + voice + speed, so
/// changing any of them misses. Small LRU — Coach sentences are short and few; Ask Anything
/// answers are never cached (the controller passes no key for them).
@MainActor
final class ReadAloudComposeCache {
    private var entries: [String: ComposedReadAloud] = [:]
    private var order: [String] = []   // least-recently-used first
    private let capacity: Int

    init(capacity: Int = 8) { self.capacity = max(1, capacity) }

    func get(_ key: String) -> ComposedReadAloud? {
        guard let value = entries[key] else { return nil }
        touch(key)
        return value
    }

    func set(_ key: String, _ value: ComposedReadAloud) {
        entries[key] = value
        touch(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
