import Foundation
import ResponsayCore

/// UI-facing dictionary operations for the Settings pane.
///
/// `ContextHotwordSettings` owns the raw persistence keys and dictionary parsing.
/// This store owns the composed actions the pane needs: manual edits, auto-term
/// confirmation/undo, learning history, and auto-learn mode selection.
struct UserDictionarySettingsStore {
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var hotwordsRaw: String {
        defaults.string(forKey: ContextHotwordSettings.defaultsKey) ?? ""
    }

    var autoHotwordsRaw: String {
        defaults.string(forKey: ContextHotwordSettings.autoDefaultsKey) ?? ""
    }

    var learningHistoryData: Data {
        defaults.data(forKey: AutoLearnHotwordHistorySettings.historyKey) ?? Data()
    }

    var autoLearnEnabled: Bool {
        AutoLearnHotwordSettings.resolve(defaults: defaults)
    }

    var explicitCorrectionLearningEnabled: Bool {
        ExplicitCorrectionLearningSettings.resolve(defaults: defaults)
    }

    var store: HotwordStore {
        ContextHotwordSettings.store(defaults: defaults)
    }

    var recentLearningRecords: [HotwordLearningRecord] {
        AutoLearnHotwordHistorySettings.records(defaults: defaults)
    }

    func replayLearnedAlias(_ sample: String) -> LearnedAliasReplay {
        HotwordLearningHistory(records: recentLearningRecords).replayLearnedAlias(in: sample)
    }

    var currentMode: AutoLearnHotwordMode {
        AutoLearnHotwordModeSettings.mode(defaults: defaults)
    }

    var confirmationPolicy: HotwordConfirmationPolicy {
        AutoLearnHotwordHistorySettings.confirmationPolicy(defaults: defaults)
    }

    @discardableResult
    func addManual(_ term: String) -> Bool {
        let value = clean(term)
        guard !value.isEmpty else { return false }
        var terms = ContextHotwordSettings.hotwords(defaults: defaults).filter { $0 != value }
        terms.insert(value, at: 0)
        defaults.set(terms.joined(separator: "\n"), forKey: ContextHotwordSettings.defaultsKey)
        return true
    }

    func delete(_ term: HotwordTerm) {
        switch term.source {
        case .manual:
            ContextHotwordSettings.removeManual(term.text, defaults: defaults)
            // 518: a manual term may carry「纠正并学习」ledger records (the learned-alias source).
            // Tombstone them like `undoAuto` does, so deleting the word also retires the alias and
            // its profile-lane echo — otherwise the Metapocalypse→Matt Pocock rewrite would keep
            // firing after the user removed the word. No-op for terms with no records.
            AutoLearnHotwordHistorySettings.markUndone(term: term.text, at: now(), defaults: defaults)
        case .auto:
            undoAuto(term.text)
        }
    }

    @discardableResult
    func rename(_ source: HotwordSource, from oldTerm: String, to newTerm: String) -> Bool {
        switch source {
        case .manual:
            return ContextHotwordSettings.renameManual(oldTerm, to: newTerm, defaults: defaults)
        case .auto:
            return ContextHotwordSettings.renameAuto(oldTerm, to: newTerm, defaults: defaults)
        }
    }

    func selectMode(_ mode: AutoLearnHotwordMode) {
        AutoLearnHotwordModeSettings.select(mode, defaults: defaults)
    }

    func setAutoLearnEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: AutoLearnHotwordSettings.key)
    }

    func setExplicitCorrectionLearningEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: ExplicitCorrectionLearningSettings.key)
    }

    func setConfirmationPolicy(_ policy: HotwordConfirmationPolicy) {
        AutoLearnHotwordHistorySettings.setConfirmationPolicy(policy, defaults: defaults)
    }

    func undoAuto(_ term: String) {
        ContextHotwordSettings.removeAuto(term, defaults: defaults)
        AutoLearnHotwordHistorySettings.markUndone(term: term, at: now(), defaults: defaults)
    }

    /// Reject a pending candidate: tombstone it (markUndone) so the flywheel won't re-learn it.
    /// It was never in the dictionary, so there is nothing to remove — unlike `undoAuto`.
    func rejectAuto(_ term: String) {
        AutoLearnHotwordHistorySettings.markUndone(term: term, at: now(), defaults: defaults)
    }

    /// 「清空学习记录」: drop the whole learning ledger AND every auto-learned dictionary term.
    /// One-shot reset of auto-learning; manual terms are left intact.
    func resetAutoLearning() {
        AutoLearnHotwordHistorySettings.clear(defaults: defaults)
        ContextHotwordSettings.clearAuto(defaults: defaults)
    }

    @discardableResult
    func confirmAuto(_ record: HotwordLearningRecord) -> Bool {
        let learnedAt = now()
        guard ContextHotwordSettings.addAuto(
            record.term,
            source: record.source,
            reason: record.reason,
            learnedAt: learnedAt,
            appName: record.appName,
            defaults: defaults
        ) else { return false }
        AutoLearnHotwordHistorySettings.markAdded(term: record.term, at: learnedAt, defaults: defaults)
        return true
    }

    private func clean(_ term: String) -> String {
        String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(HotwordStore.maxTermLength))
    }
}
