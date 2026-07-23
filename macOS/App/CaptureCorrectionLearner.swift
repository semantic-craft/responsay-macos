import Foundation
import ResponsayCore

/// 518 — the capsule「纠正并学习」confirm action. One explicit user correction ("这个词错了,
/// 应该是 X") feeds BOTH biasing ends at once, bypassing the auto-learn phonetic gate entirely:
/// - the manual dictionary (`ContextHotwordSettings.addManual`) → provider biasing / weak-prompt
///   source biasing;
/// - a learned-alias ledger record (`sourceTerm → term`) → `HotwordHardMatch.enforce` repairs the
///   SAME mishear deterministically on the next dictation.
enum CaptureCorrectionLearner {
    enum Outcome: Equatable {
        case learned
        case rejected(reason: String)
    }

    /// Validates, writes the dictionary + alias record (both idempotent), then notifies.
    /// `reason` is the content-free provenance stamped on the ledger record (default = the manual
    /// 「纠正并学习」correction; the #565 confirm path passes 「用户确认候选」). `notify` defaults to the
    /// auto-learn toast notification (「已加入识别词典」).
    @discardableResult
    static func learn(
        wrong rawWrong: String,
        correct rawCorrect: String,
        reason: String = "用户手动纠正",
        defaults: UserDefaults = .standard,
        notify: (String) -> Void = { term in
            NotificationCenter.default.post(
                name: .autoLearnHotwordDidAdd, object: nil, userInfo: ["term": term])
        }
    ) -> Outcome {
        let wrong = rawWrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = rawCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correct.isEmpty else { return .rejected(reason: "请填写正确写法") }
        guard !wrong.isEmpty else { return .rejected(reason: "请点选或填写听错的词") }
        guard wrong != correct else { return .rejected(reason: "两边相同，无需纠正") }

        // Dictionary write dedupes itself (false = already present — not a failure here).
        _ = ContextHotwordSettings.addManual(correct, defaults: defaults)

        // Alias write is idempotent: skip when this exact mapping is already live in the ledger.
        let history = HotwordLearningHistory(records: AutoLearnHotwordHistorySettings.records(defaults: defaults))
        if history.learnedAliases()[wrong] != correct {
            AutoLearnHotwordHistorySettings.append(
                HotwordCandidateProposal(
                    term: correct, source: .manual, confidence: 1.0,
                    reason: reason, sourceTerm: wrong),
                status: .added, defaults: defaults)
        }
        notify(correct)
        return .learned
    }
}
