import Foundation
import ResponsayCore

private struct HotwordLearningFunctionalState: Codable, Equatable {
    var learnedAliases: [String: String] = [:]
    var tombstonedTerms: Set<String> = []

    mutating func apply(_ records: [HotwordLearningRecord]) {
        // The ledger is newest-first. Replay oldest-first so the latest decisive record wins.
        for record in records.reversed() {
            apply(record)
        }
    }

    mutating func apply(_ record: HotwordLearningRecord) {
        switch record.status {
        case .added:
            tombstonedTerms.remove(record.term)
            guard let source = record.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty, source != record.term else { return }
            learnedAliases[source] = record.term
        case .undone:
            tombstone(record.term)
        case .pending, .ignored:
            break
        }
    }

    mutating func tombstone(_ term: String) {
        tombstonedTerms.insert(term)
        learnedAliases = learnedAliases.filter { $0.value != term }
    }
}

enum AutoLearnHotwordHistorySettings {
    static let confirmationPolicyKey = "hotword.autoLearn.confirmationPolicy"
    static let historyKey = "hotword.autoLearn.history"
    private static let functionalStateKey = "hotword.autoLearn.functionalState.v1"

    static func confirmationPolicy(defaults: UserDefaults = .standard) -> HotwordConfirmationPolicy {
        guard let raw = defaults.string(forKey: confirmationPolicyKey),
              let policy = HotwordConfirmationPolicy(rawValue: raw) else {
            return .autoAddHighConfidence
        }
        return policy
    }

    static func setConfirmationPolicy(
        _ policy: HotwordConfirmationPolicy,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(policy.rawValue, forKey: confirmationPolicyKey)
    }

    static func rawRecords(defaults: UserDefaults = .standard) -> [HotwordLearningRecord] {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([HotwordLearningRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Read the learning ledger after applying the same retention period as dictation history.
    /// The durable recognition dictionary uses separate keys and is intentionally untouched.
    static func records(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [HotwordLearningRecord] {
        let decoded = rawRecords(defaults: defaults)
        // Migrate aliases and tombstones before the first retention pass removes old audit rows.
        _ = functionalState(
            defaults: defaults,
            fallbackRecords: decoded,
            persistMigration: true)
        guard let cutoff = HistoryRetentionSettings.period(defaults: defaults).cutoff(relativeTo: now) else {
            return decoded
        }
        let retained = decoded.filter { $0.learnedAt > cutoff }
        if retained.count != decoded.count {
            persist(retained, defaults: defaults)
        }
        return retained
    }

    /// Read-only retained view for latency-sensitive ASR/profile paths that promise not to write.
    /// Startup and audit reads call `records` to migrate and physically remove the same expired rows.
    static func retainedRecords(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [HotwordLearningRecord] {
        let decoded = rawRecords(defaults: defaults)
        guard let cutoff = HistoryRetentionSettings.period(defaults: defaults).cutoff(relativeTo: now) else {
            return decoded
        }
        return decoded.filter { $0.learnedAt > cutoff }
    }

    @discardableResult
    static func save(_ records: [HotwordLearningRecord], defaults: UserDefaults = .standard) -> Bool {
        persist(Array(records.prefix(30)), defaults: defaults)
    }

    @discardableResult
    private static func persist(
        _ records: [HotwordLearningRecord],
        defaults: UserDefaults
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(records) else { return false }
        var state = functionalState(defaults: defaults)
        state.apply(records)
        defaults.set(data, forKey: historyKey)
        persistFunctionalState(state, defaults: defaults)
        if defaults === UserDefaults.standard {
            DictationLexicalProfileSettings.scheduleRefresh()
        }
        return true
    }

    @discardableResult
    static func append(
        _ proposal: HotwordCandidateProposal,
        status: HotwordLearningRecordStatus,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        var history = HotwordLearningHistory(records: records(defaults: defaults))
        history.record(proposal, status: status, at: date)
        return save(history.records, defaults: defaults)
    }

    @discardableResult
    static func markUndone(term: String, at date: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        var history = HotwordLearningHistory(records: records(defaults: defaults))
        let didMarkLedger = history.markUndone(term: term, at: date)
        var state = functionalState(defaults: defaults)
        state.tombstone(term)
        persistFunctionalState(state, defaults: defaults)
        guard didMarkLedger else {
            if defaults === UserDefaults.standard {
                DictationLexicalProfileSettings.scheduleRefresh()
            }
            return false
        }
        return save(history.records, defaults: defaults)
    }

    @discardableResult
    static func markAdded(term: String, at date: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        var history = HotwordLearningHistory(records: records(defaults: defaults))
        history.markAdded(term: term, at: date)
        return save(history.records, defaults: defaults)
    }

    /// Wipe the whole learning ledger (the 「清空学习记录」 reset). Drops every record — pending,
    /// added, ignored and the `.undone` tombstones — so nothing lingers across reinstalls.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: functionalStateKey)
        if defaults === UserDefaults.standard {
            DictationLexicalProfileSettings.scheduleRefresh()
        }
    }

    static func learnedAliases(defaults: UserDefaults = .standard) -> [String: String] {
        let state = functionalState(defaults: defaults)
        return state.learnedAliases.filter { !state.tombstonedTerms.contains($0.value) }
    }

    static func tombstonedTerms(defaults: UserDefaults = .standard) -> Set<String> {
        return functionalState(defaults: defaults).tombstonedTerms
    }

    private static func functionalState(
        defaults: UserDefaults,
        fallbackRecords: [HotwordLearningRecord]? = nil,
        persistMigration: Bool = false
    ) -> HotwordLearningFunctionalState {
        if let data = defaults.data(forKey: functionalStateKey),
           let decoded = try? JSONDecoder().decode(HotwordLearningFunctionalState.self, from: data) {
            return decoded
        }
        var migrated = HotwordLearningFunctionalState()
        migrated.apply(fallbackRecords ?? rawRecords(defaults: defaults))
        if persistMigration {
            persistFunctionalState(migrated, defaults: defaults)
        }
        return migrated
    }

    private static func persistFunctionalState(
        _ state: HotwordLearningFunctionalState,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: functionalStateKey)
    }
}
