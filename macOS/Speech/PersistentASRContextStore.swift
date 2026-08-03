import Foundation
import os
import ResponsayCore

/// Local, privacy-bounded persistence for Qwen Flash Streaming's official ASR Context input.
///
/// The payload intentionally contains only a target Bundle ID, the model's raw final text, a local
/// identifier, and its capture time. It never serializes a Qwen request/config (which contains the
/// API key), audio, partial hypotheses, downstream rewrites, or assistant messages.
@MainActor
final class PersistentASRContextStore {
    static let maximumItemsPerBundleID = 5
    static let maximumCharactersPerItem = 400
    static let timeToLive: TimeInterval = 2 * 60 * 60
    static let defaultFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
        .appendingPathComponent("qwen-asr-context-v1.json")

    private static let log = Logger(
        subsystem: AppBrand.loggerSubsystem,
        category: "persistent-asr-context")

    struct Item: Codable, Equatable {
        var id: UUID
        var bundleIdentifier: String
        var rawFinalText: String
        var capturedAt: Date
    }

    private struct Payload: Codable, Equatable {
        var schemaVersion = 1
        var items: [Item] = []
    }

    private let fileURL: URL
    private let now: @MainActor () -> Date

    init(
        fileURL: URL = PersistentASRContextStore.defaultFileURL,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    /// Reads one Bundle-ID bucket after physically enforcing TTL and count limits for every bucket.
    func items(for bundleIdentifier: String) -> [Item] {
        let payload = readAndPrune().payload
        guard let bundleIdentifier = Self.cleanBundleIdentifier(bundleIdentifier) else { return [] }
        return payload.items.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Test/startup seam that also guarantees a physical cleanup pass across all buckets.
    func allItems() -> [Item] {
        readAndPrune().payload.items
    }

    /// Stores one raw server-final segment. Cleanup runs even when the supplied item is invalid.
    @discardableResult
    func record(_ rawFinalText: String, scope bundleIdentifier: String) -> UUID? {
        let readResult = readAndPrune()
        guard readResult.succeeded else { return nil }
        var payload = readResult.payload
        guard let bundleIdentifier = Self.cleanBundleIdentifier(bundleIdentifier),
              let rawFinalText = Self.cleanRawFinalText(rawFinalText) else { return nil }
        let item = Item(
            id: UUID(),
            bundleIdentifier: bundleIdentifier,
            rawFinalText: rawFinalText,
            capturedAt: now())
        payload.items.append(item)
        payload = pruned(payload, relativeTo: now())
        return persist(payload) ? item.id : nil
    }

    @discardableResult
    func cleanup() -> Bool {
        guard preparePrivateDirectory() else { return false }
        return readAndPrune().succeeded
    }

    @discardableResult
    func clear() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            Self.log.error("Persistent ASR Context removal failed")
            return false
        }
    }

    private func readAndPrune() -> (payload: Payload, succeeded: Bool) {
        let loadResult = load()
        guard loadResult.succeeded else { return (Payload(), false) }
        let loaded = loadResult.payload
        let cleaned = pruned(loaded, relativeTo: now())
        if cleaned != loaded {
            return (cleaned, persist(cleaned))
        }
        return (cleaned, true)
    }

    private func load() -> (payload: Payload, succeeded: Bool) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (Payload(), true) }
        guard hardenExistingStorage() else {
            let removed = clear()
            return (Payload(), removed)
        }
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == 1 else {
            // Corrupt/unknown data must fail closed, never leak entries across Bundle IDs.
            return (Payload(), clear())
        }
        return (payload, true)
    }

    private func pruned(_ payload: Payload, relativeTo date: Date) -> Payload {
        let cutoff = date.addingTimeInterval(-Self.timeToLive)
        let cleaned = payload.items.enumerated().compactMap { index, item -> (Int, Item)? in
            guard let bundleIdentifier = Self.cleanBundleIdentifier(item.bundleIdentifier),
                  let rawFinalText = Self.cleanRawFinalText(item.rawFinalText),
                  item.capturedAt > cutoff,
                  item.capturedAt <= date else { return nil }
            return (index, Item(
                id: item.id,
                bundleIdentifier: bundleIdentifier,
                rawFinalText: rawFinalText,
                capturedAt: item.capturedAt))
        }
        .sorted { lhs, rhs in
            if lhs.1.capturedAt != rhs.1.capturedAt {
                return lhs.1.capturedAt < rhs.1.capturedAt
            }
            return lhs.0 < rhs.0
        }

        var counts: [String: Int] = [:]
        var newestFirst = [Item]()
        for (_, item) in cleaned.reversed() {
            let count = counts[item.bundleIdentifier, default: 0]
            guard count < Self.maximumItemsPerBundleID else { continue }
            counts[item.bundleIdentifier] = count + 1
            newestFirst.append(item)
        }
        return Payload(items: Array(newestFirst.reversed()))
    }

    private func persist(_ payload: Payload) -> Bool {
        guard !payload.items.isEmpty else {
            return clear()
        }
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        guard preparePrivateDirectory() else { return false }
        do {
            // The containing directory is already 0700, so Foundation's atomic temporary file is
            // never visible to other local users before the final file is tightened to 0600.
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path)
            return true
        } catch {
            // If publication succeeded but permission hardening did not, fail closed by removing
            // the newly written Context rather than leaving a file with unintended permissions.
            _ = clear()
            Self.log.error("Persistent ASR Context write or permission hardening failed")
            return false
        }
    }

    private func preparePrivateDirectory() -> Bool {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path)
            return true
        } catch {
            Self.log.error("Persistent ASR Context directory hardening failed")
            return false
        }
    }

    private func hardenExistingStorage() -> Bool {
        guard preparePrivateDirectory() else { return false }
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path)
            return true
        } catch {
            Self.log.error("Persistent ASR Context file hardening failed")
            return false
        }
    }

    private static func cleanBundleIdentifier(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanRawFinalText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maximumCharactersPerItem))
    }
}

@MainActor
enum PersistentASRContextSettings {
    static let enabledKey = "qwenASRPersistentContextEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    @discardableResult
    static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        fileURL: URL = PersistentASRContextStore.defaultFileURL
    ) -> Bool {
        let store = PersistentASRContextStore(fileURL: fileURL)
        if enabled {
            guard store.cleanup() else {
                defaults.set(false, forKey: enabledKey)
                _ = store.clear()
                return false
            }
        } else {
            // Opt-out is fail-closed even if a filesystem error prevents immediate deletion:
            // future reads/writes ignore the residual file and keep retrying its removal.
            defaults.set(false, forKey: enabledKey)
            guard store.clear() else {
                return false
            }
        }
        defaults.set(enabled, forKey: enabledKey)
        return true
    }

    @discardableResult
    static func clear(
        defaults _: UserDefaults = .standard,
        fileURL: URL = PersistentASRContextStore.defaultFileURL
    ) -> Bool {
        PersistentASRContextStore(fileURL: fileURL).clear()
    }

    static func prepareAtLaunch(
        defaults: UserDefaults = .standard,
        fileURL: URL = PersistentASRContextStore.defaultFileURL,
        now: Date = Date()
    ) {
        let store = PersistentASRContextStore(fileURL: fileURL, now: { now })
        if isEnabled(defaults: defaults) {
            if !store.cleanup() {
                defaults.set(false, forKey: enabledKey)
                _ = store.clear()
            }
        } else {
            _ = store.clear()
        }
    }
}
