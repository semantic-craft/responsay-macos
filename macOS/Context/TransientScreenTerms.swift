import Foundation
import ResponsayCore
import os

/// 517 — this capture's transient ASR bias terms, harvested from the visible screen at capture
/// start (真·屏幕感知辅助识别). Weak-prompt lane ONLY: the terms never touch the dictionary,
/// hard-match or disk — they live in memory for one capture and are
/// replaced at the next `beginHarvest`, so screen noise can never be "learned".
enum TransientScreenTerms {
    private static let store = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// The current capture's harvested terms (empty when 屏幕上下文 is off or nothing landed yet).
    static var current: [String] { store.withLock { $0 } }

    static func set(_ terms: [String]) { store.withLock { $0 = terms } }

    static func clear() { set([]) }

    /// Called from capture start: reset the stash, then harvest OFF the hot path. Returns
    /// synchronously — the Fn→录音 path never waits on AX. Fail-open: a slow or failed collect
    /// just means this capture gets no transient terms. Returns the spawned task (nil when
    /// 屏幕上下文 is off) so tests can await the landing deterministically.
    @discardableResult
    static func beginHarvest(
        isEnabled: Bool = ScreenContextSettings.isEnabled,
        dictionaryTerms: @escaping @Sendable () -> [String] = { ContextHotwordSettings.biasingSets().weakPrompt },
        collect: @escaping @Sendable () async -> String? = { VisibleTextCollector.collect(from: nil) }
    ) -> Task<Void, Never>? {
        clear()
        guard isEnabled else { return nil }
        return Task.detached(priority: .utility) {
            guard let text = await collect(), !text.isEmpty else { return }
            set(ScreenTermHarvester.harvest(text, excluding: dictionaryTerms()))
        }
    }
}
