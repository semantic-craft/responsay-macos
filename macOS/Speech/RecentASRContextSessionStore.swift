import Foundation
import ResponsayCore

/// Process-memory context for Qwen streaming ASR. No disk reads or writes: persistence is a
/// separate, opt-in product decision. The target app Bundle ID is the isolation boundary.
@MainActor
final class RecentASRContextSessionStore {
    static let shared = RecentASRContextSessionStore()

    private var buffer = RecentASRContextBuffer()

    func context(for scope: String?) -> [String] {
        guard let scope else { return [] }
        return buffer.context(
            for: scope,
            learnedAliases: ContextHotwordSettings.biasingSets().learnedAliases)
    }

    @discardableResult
    func record(_ rawFinalText: String, scope: String?) -> [String] {
        guard let scope else { return [] }
        buffer.record(rawFinalText, scope: scope)
        return context(for: scope)
    }
}
