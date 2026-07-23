import Foundation

public struct HotwordLearningHistory: Sendable, Equatable {
    public private(set) var records: [HotwordLearningRecord]
    private let limit: Int

    public init(records: [HotwordLearningRecord] = [], limit: Int = 30) {
        self.records = Array(records.prefix(limit))
        self.limit = limit
    }

    public mutating func record(
        _ proposal: HotwordCandidateProposal,
        status: HotwordLearningRecordStatus,
        at date: Date = Date()
    ) {
        records.insert(
            HotwordLearningRecord(
                term: proposal.term,
                source: proposal.source,
                status: status,
                reason: proposal.reason,
                learnedAt: date,
                sourceTerm: proposal.sourceTerm,
                appName: proposal.appName,
                windowTitle: proposal.windowTitle,
                confidence: proposal.confidence),
            at: 0)
        records = Array(records.prefix(limit))
    }

    @discardableResult
    public mutating func markUndone(term: String, at date: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.term == term }) else { return false }
        records[index].status = .undone
        records[index].learnedAt = date
        return true
    }

    @discardableResult
    public mutating func markAdded(term: String, at date: Date = Date()) -> Bool {
        guard let index = records.firstIndex(where: { $0.term == term && $0.status == .pending })
            ?? records.firstIndex(where: { $0.term == term }) else { return false }
        records[index].status = .added
        records[index].learnedAt = date
        return true
    }

    /// 445 — terms the user undid and has not re-added since, so the auto-learn flywheel won't
    /// put them back. Records are newest-first; a term is tombstoned when its newest *decisive*
    /// record (`.undone` or `.added`) is `.undone`. `.ignored`/`.pending` don't count, so the
    /// `.ignored` rows left by suppressed re-attempts never clear the tombstone.
    public func tombstonedTerms() -> Set<String> {
        var tombstoned = Set<String>()
        var decided = Set<String>()
        for record in records where record.status == .undone || record.status == .added {
            guard decided.insert(record.term).inserted else { continue }
            if record.status == .undone { tombstoned.insert(record.term) }
        }
        return tombstoned
    }

    /// Surfaces from explicit successful corrections, newest wins: `sourceTerm -> term`.
    public func learnedAliases() -> [String: String] {
        let tombstoned = tombstonedTerms()
        var aliases: [String: String] = [:]
        for record in records where record.status == .added && !tombstoned.contains(record.term) {
            guard let source = record.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty, source != record.term, aliases[source] == nil else {
                continue
            }
            aliases[source] = record.term
        }
        return aliases
    }

    public func replayLearnedAlias(
        in sample: String,
        protectedContext: Bool = false
    ) -> LearnedAliasReplay {
        if protectedContext {
            return LearnedAliasReplay(
                status: .protectedContext,
                sourceTerm: nil,
                term: nil,
                outputText: nil,
                reason: "受保护场景不会参与长期 learned alias")
        }

        let text = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return LearnedAliasReplay(
                status: .notMatched,
                sourceTerm: nil,
                term: nil,
                outputText: nil,
                reason: "测试文本为空")
        }

        let tombstoned = tombstonedTerms()
        var hasAlias = false
        for record in records {
            guard let source = record.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty, source != record.term else { continue }
            hasAlias = true

            let preview = HotwordHardMatch.enforce(
                text,
                userTerms: [],
                seedTerms: [],
                learnedAliases: [source: record.term])
            guard !preview.replacements.isEmpty else { continue }

            if record.status == .undone || tombstoned.contains(record.term) {
                return LearnedAliasReplay(
                    status: .tombstoned,
                    sourceTerm: source,
                    term: record.term,
                    outputText: nil,
                    reason: "这条 learned alias 已撤销")
            }

            switch record.status {
            case .added:
                return LearnedAliasReplay(
                    status: .matched,
                    sourceTerm: source,
                    term: record.term,
                    outputText: preview.text,
                    reason: "会参与本地 hard-match")
            case .pending, .ignored:
                return LearnedAliasReplay(
                    status: .lowConfidence,
                    sourceTerm: source,
                    term: record.term,
                    outputText: nil,
                    reason: record.status == .pending ? "待确认，批准后才生效" : record.reason)
            case .undone:
                break
            }
        }

        return LearnedAliasReplay(
            status: .notMatched,
            sourceTerm: nil,
            term: nil,
            outputText: nil,
            reason: hasAlias ? "已有 learned alias，但测试文本没有命中误识别表面" : "没有 learned alias 记录")
    }
}

public struct LearnedAliasReplay: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case matched
        case notMatched
        case tombstoned
        case protectedContext
        case lowConfidence
    }

    public let status: Status
    public let sourceTerm: String?
    public let term: String?
    public let outputText: String?
    public let reason: String

    public init(
        status: Status,
        sourceTerm: String?,
        term: String?,
        outputText: String?,
        reason: String
    ) {
        self.status = status
        self.sourceTerm = sourceTerm
        self.term = term
        self.outputText = outputText
        self.reason = reason
    }
}
