import Foundation
import ResponsayCore

enum AutoLearnHotwordHistorySettings {
    static let confirmationPolicyKey = "hotword.autoLearn.confirmationPolicy"
    static let historyKey = "hotword.autoLearn.history"

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

    static func records(defaults: UserDefaults = .standard) -> [HotwordLearningRecord] {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([HotwordLearningRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    @discardableResult
    static func save(_ records: [HotwordLearningRecord], defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(Array(records.prefix(30))) else { return false }
        defaults.set(data, forKey: historyKey)
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
        history.markUndone(term: term, at: date)
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
        if defaults === UserDefaults.standard {
            DictationLexicalProfileSettings.scheduleRefresh()
        }
    }
}
