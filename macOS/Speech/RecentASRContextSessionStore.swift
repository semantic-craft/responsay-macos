import Foundation
import ResponsayCore

/// Current-process context plus optional, bounded recovery for Qwen streaming ASR. The target app
/// Bundle ID is the only isolation key; an unknown target always fails closed.
@MainActor
final class RecentASRContextSessionStore {
    static let shared = RecentASRContextSessionStore()

    private struct SessionItem {
        var persistentID: UUID?
        var rawFinalText: String
        var capturedAt: Date
    }

    private let defaults: UserDefaults
    private let persistentStore: PersistentASRContextStore
    private let now: @MainActor () -> Date
    private var itemsByBundleIdentifier: [String: [SessionItem]] = [:]

    init(
        defaults: UserDefaults = .standard,
        fileURL: URL = PersistentASRContextStore.defaultFileURL,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.defaults = defaults
        persistentStore = PersistentASRContextStore(
            fileURL: fileURL,
            now: now,
            persistenceFailure: {
                defaults.set(false, forKey: PersistentASRContextSettings.enabledKey)
            })
        self.now = now
    }

    func context(for scope: String?) -> [String] {
        let persistentEnabled = PersistentASRContextSettings.isEnabled(defaults: defaults)
        if !persistentEnabled {
            persistentStore.clear()
        }
        guard let scope = Self.cleanScope(scope) else {
            if persistentEnabled { persistentStore.cleanup() }
            return []
        }

        let sessionItems = itemsByBundleIdentifier[scope] ?? []
        let rawContext: [String]
        if persistentEnabled {
            let persisted = persistentStore.items(for: scope)
            let persistedIDs = Set(persisted.map(\.id))
            let cutoff = now().addingTimeInterval(-PersistentASRContextStore.timeToLive)
            let ephemeral = sessionItems.filter { item in
                let isAlreadyPersisted = item.persistentID.map(persistedIDs.contains) ?? false
                return !isAlreadyPersisted && item.capturedAt > cutoff
            }
            let combined = persisted.enumerated().map { index, item in
                (item.capturedAt, index, item.rawFinalText)
            } + ephemeral.enumerated().map { index, item in
                (item.capturedAt, persisted.count + index, item.rawFinalText)
            }
            rawContext = combined.sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }.suffix(PersistentASRContextStore.maximumItemsPerBundleID).map { $0.2 }
        } else {
            rawContext = sessionItems.map(\.rawFinalText)
        }

        let aliases = ContextHotwordSettings.biasingSets(defaults: defaults).learnedAliases
        guard !aliases.isEmpty else { return rawContext }
        return rawContext.map {
            HotwordHardMatch.enforce(
                $0,
                userTerms: [],
                seedTerms: [],
                learnedAliases: aliases).text
        }
    }

    @discardableResult
    func record(_ rawFinalText: String, scope: String?) -> [String] {
        let persistentEnabled = PersistentASRContextSettings.isEnabled(defaults: defaults)
        if !persistentEnabled {
            persistentStore.clear()
        }
        guard let scope = Self.cleanScope(scope),
              let rawFinalText = Self.cleanRawFinalText(rawFinalText) else {
            if persistentEnabled { persistentStore.cleanup() }
            return []
        }
        let persistentID: UUID?
        if persistentEnabled {
            persistentID = persistentStore.record(rawFinalText, scope: scope)
            if persistentID == nil {
                // A runtime storage failure must not leave the UI promising restart recovery.
                // Keep this final result in current-session memory, but fail persistent Context off.
                defaults.set(false, forKey: PersistentASRContextSettings.enabledKey)
                _ = persistentStore.clear()
            }
        } else {
            persistentID = nil
        }
        var items = itemsByBundleIdentifier[scope, default: []]
        items.append(SessionItem(
            persistentID: persistentID,
            rawFinalText: rawFinalText,
            capturedAt: now()))
        itemsByBundleIdentifier[scope] = Array(
            items.suffix(PersistentASRContextStore.maximumItemsPerBundleID))
        return context(for: scope)
    }

    private static func cleanScope(_ scope: String?) -> String? {
        guard let scope else { return nil }
        let cleaned = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanRawFinalText(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(PersistentASRContextStore.maximumCharactersPerItem))
    }
}
