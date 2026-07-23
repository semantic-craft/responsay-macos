import AppKit
import ResponsayCore

extension DictionarySettingsPane {
    // MARK: - Data plumbing (same stores as the old SettingsContextSection)

    var store: HotwordStore {
        _ = hotwords
        _ = autoHotwords
        return dictionaryStore.store
    }

    var isAutoLearnEnabled: Bool {
        _ = autoLearnEnabled
        return dictionaryStore.autoLearnEnabled
    }

    var autoLearnStatusText: String {
        if isAutoLearnEnabled {
            guard AccessibilityPermission.isTrusted else {
                return "需开启辅助功能：否则无法观察你在其他 App 里的纠正"
            }
            return "已开启：会从你纠正 Responsay 刚写入的词中学习候选热词"
        }
        return "已关闭：停止学习新热词，只使用现有词典"
    }

    var autoLearnStatusState: StatusDot.State {
        guard isAutoLearnEnabled else { return .gray }
        return AccessibilityPermission.isTrusted ? .green : .amber
    }

    var recentLearningRecords: [HotwordLearningRecord] {
        _ = learningHistoryData
        return dictionaryStore.recentLearningRecords
    }

    var cleanNewTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanEditingText: String {
        editingText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredTerms: [HotwordTerm] {
        let sourceFiltered: [HotwordTerm]
        switch filter {
        case .all: sourceFiltered = store.userTermEntries
        case .auto: sourceFiltered = store.userTermEntries(source: .auto)
        case .manual: sourceFiltered = store.userTermEntries(source: .manual)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sourceFiltered }
        return sourceFiltered.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func count(for option: HotwordFilter) -> Int {
        switch option {
        case .all: return store.userTermEntries.count
        case .auto: return store.userTermEntries(source: .auto).count
        case .manual: return store.userTermEntries(source: .manual).count
        }
    }

    func addManualTerm() {
        guard dictionaryStore.addManual(cleanNewTerm) else { return }
        refreshDictionaryBindings()
        newTerm = ""
        filter = .all
    }

    func delete(_ term: HotwordTerm) {
        dictionaryStore.delete(term)
        refreshDictionaryBindings()
        if isEditing(term) {
            cancelEditing()
        }
    }

    func beginEditing(_ term: HotwordTerm) {
        editingSource = term.source
        editingOriginalText = term.text
        editingText = term.text
    }

    func cancelEditing() {
        editingSource = nil
        editingOriginalText = ""
        editingText = ""
    }

    func isEditing(_ term: HotwordTerm) -> Bool {
        editingSource == term.source && editingOriginalText == term.text
    }

    func saveEditingTerm() {
        guard let editingSource, !cleanEditingText.isEmpty else { return }
        let didRename = dictionaryStore.rename(editingSource, from: editingOriginalText, to: editingText)
        guard didRename else {
            NSSound.beep()
            return
        }
        refreshDictionaryBindings()
        cancelEditing()
    }

    func undo(_ term: String) {
        dictionaryStore.undoAuto(term)
        refreshDictionaryBindings()
    }

    func confirm(_ record: HotwordLearningRecord) {
        guard dictionaryStore.confirmAuto(record) else { return }
        refreshDictionaryBindings()
    }

    func reject(_ record: HotwordLearningRecord) {
        dictionaryStore.rejectAuto(record.term)
        refreshDictionaryBindings()
    }

    /// 「清空学习记录」: wipe the ledger and every auto-learned term in one shot. Manual terms stay.
    func clearLearning() {
        dictionaryStore.resetAutoLearning()
        aliasReplayResult = nil
        refreshDictionaryBindings()
    }

    func runAliasReplay() {
        aliasReplayResult = dictionaryStore.replayLearnedAlias(aliasReplayText)
    }

    func refreshDictionaryBindings() {
        hotwords = dictionaryStore.hotwordsRaw
        autoHotwords = dictionaryStore.autoHotwordsRaw
        autoLearnEnabled = dictionaryStore.autoLearnEnabled
        confirmationPolicyRaw = dictionaryStore.confirmationPolicy.rawValue
        learningHistoryData = dictionaryStore.learningHistoryData
    }

    func termDetail(_ term: HotwordTerm) -> String? {
        guard term.source == .auto else { return nil }
        if let learnedSource = term.learnedSource, let learnedAt = term.learnedAt {
            return "\(learnedSource.displayName) · \(learnedAt.formatted(date: .numeric, time: .shortened))"
        }
        if let learnedSource = term.learnedSource {
            return learnedSource.displayName
        }
        return "自动添加"
    }

    func recordStatusSymbol(_ status: HotwordLearningRecordStatus) -> String {
        switch status {
        case .pending: return "questionmark.circle"
        case .added: return "checkmark.circle"
        case .ignored: return "minus.circle"
        case .undone: return "arrow.uturn.backward.circle"
        }
    }

    /// 454 — one-line provenance for an audit row: 误→正 · 来源 · App · 置信度. The bucket header
    /// already shows the status, so it's omitted here.
    func auditRowSubtitle(_ row: LearningAuditGroups.Row) -> String {
        let record = row.record
        let correction = record.sourceTerm.map { "\($0) → \(record.term)" }
        let app = (record.appName?.isEmpty == false) ? record.appName : nil
        let parts = [
            correction,
            record.source.displayName,
            app,
            confidenceText(record.confidence)
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    func auditRowTitle(_ record: HotwordLearningRecord) -> String {
        guard let source = record.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty, source != record.term else {
            return record.term
        }
        return "\(source) → \(record.term)"
    }

    func isLearnedAlias(_ record: HotwordLearningRecord) -> Bool {
        auditRowTitle(record) != record.term
    }

    func aliasReplaySummary(_ replay: LearnedAliasReplay) -> String {
        let pair = [replay.sourceTerm, replay.term].compactMap { $0 }.joined(separator: " → ")
        let prefix = pair.isEmpty ? "" : "\(pair) · "
        switch replay.status {
        case .matched:
            return "\(prefix)命中：\(replay.reason) · 输出：\(replay.outputText ?? "")"
        case .notMatched:
            return "\(prefix)未命中：\(replay.reason)"
        case .tombstoned:
            return "\(prefix)未生效：\(replay.reason)"
        case .protectedContext:
            return "\(prefix)未生效：\(replay.reason)"
        case .lowConfidence:
            return "\(prefix)未生效：\(replay.reason)"
        }
    }

    func confidenceText(_ confidence: Double?) -> String? {
        guard let confidence else { return nil }
        return "置信 \(Int((confidence * 100).rounded()))%"
    }

    /// Chinese label for why a term is interrupt-worthy (nil = ordinary, no badge).
    func sensitivityLabel(_ reason: SpecializedReason?) -> String? {
        switch reason {
        case .caseNumber: return "案号"
        case .legalGazetteer: return "法律词"
        case .personalName: return "人名"
        case .organizationName: return "机构"
        case .placeName: return "地名"
        case nil: return nil
        }
    }
}
