import Foundation

/// A detected heading cue → a built `LegalStage` hint + confidence boost (issue 116).
public struct HeadingSignal: Codable, Sendable, Equatable {
    public let rawText: String
    public let normalized: String
    public let stageHint: LegalStage
    public let confidenceBoost: Double
    public let reason: String

    public init(rawText: String, normalized: String, stageHint: LegalStage,
                confidenceBoost: Double, reason: String) {
        self.rawText = rawText
        self.normalized = normalized
        self.stageHint = stageHint
        self.confidenceBoost = confidenceBoost
        self.reason = reason
    }
}

/// Rules-first heading detection over `textBeforeCursor` (~700 chars) + window
/// title — heading cues are more stable than full-text semantics (issue 116).
/// All cues map onto the **built** `LegalStage`; no parallel enum.
public struct HeadingDetector: Sendable {
    public init() {}

    /// Detected heading signals (usually 0–1), strongest-first.
    public func detect(textBeforeCursor: String?, windowTitle: String?) -> [HeadingSignal] {
        let haystack = [windowTitle, textBeforeCursor].compactMap { $0 }.joined(separator: "\n")
        guard !haystack.isEmpty else { return [] }

        var signals: [HeadingSignal] = []
        for rule in Self.rules where haystack.contains(rule.cue) {
            signals.append(HeadingSignal(
                rawText: rule.cue, normalized: rule.cue, stageHint: rule.stage,
                confidenceBoost: rule.boost, reason: "标题线索「\(rule.cue)」→ \(rule.stage.rawValue)"
            ))
        }
        return signals.sorted { $0.confidenceBoost > $1.confidenceBoost }
    }

    private struct Rule {
        let cue: String
        let stage: LegalStage
        let boost: Double
    }

    // Each cue → an EXISTING LegalStage case (no enum extension needed in v0).
    private static let rules: [Rule] = [
        Rule(cue: "事实与理由", stage: .briefDrafting, boost: 0.6),
        Rule(cue: "起诉状", stage: .matterIntake, boost: 0.5),
        Rule(cue: "答辩状", stage: .matterIntake, boost: 0.5),
        Rule(cue: "证据目录", stage: .evidenceReview, boost: 0.6),
        Rule(cue: "证明目的", stage: .evidenceReview, boost: 0.5),
        Rule(cue: "争议焦点", stage: .argumentDrafting, boost: 0.5),
        Rule(cue: "参考文献", stage: .citationDrafting, boost: 0.6),
        Rule(cue: "注释", stage: .citationDrafting, boost: 0.3),
        Rule(cue: "脚注", stage: .citationDrafting, boost: 0.3),
        Rule(cue: "数据处理场景", stage: .productReview, boost: 0.5),
        Rule(cue: "PRD", stage: .productReview, boost: 0.4),
        Rule(cue: "上线评审", stage: .productReview, boost: 0.5),
    ]
}
