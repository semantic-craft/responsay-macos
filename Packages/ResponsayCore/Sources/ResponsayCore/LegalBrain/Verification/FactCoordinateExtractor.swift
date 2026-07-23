import Foundation

// MARK: - 108 FactCoordinateExtractor (a.k.a. DeterministicLegalCoordinateExtractor, v0.2 §14)
//
// A local, deterministic (regex + small dictionary) extractor for fact coordinates:
// 法条号 / 案号 / 日期 / 金额 / 标准号. Runs after skill execution to back-fill any
// `[待核]` anchor the model missed (and could feed the ContextSignalLayer, 113).
// It NEVER claims verification — every extracted anchor is `.pending` (= [待核]).
// Foundation-only; outputs use the built `VerificationAnchor` (no parallel type).

public struct FactCoordinateExtractor: Sendable {
    public init() {}

    /// Pending `[待核]` anchors for every fact coordinate found in `text`, de-duplicated
    /// by label, in first-seen order.
    public func extract(from text: String) -> [VerificationAnchor] {
        guard !text.isEmpty else { return [] }
        var seen = Set<String>()
        var anchors: [VerificationAnchor] = []
        for rule in Self.rules {
            for raw in Self.matches(of: rule.pattern, in: text) {
                var label = Self.normalize(raw)
                if rule.kind == .officialDocument { label = Self.stripLeadIn(label) }
                guard label.count >= rule.minLength, !seen.contains(label) else { continue }
                seen.insert(label)
                anchors.append(VerificationAnchor(
                    id: "\(rule.kind.rawValue):\(label)",
                    label: label,
                    kind: rule.kind,
                    status: .pending,
                    query: label,
                    preferredSources: rule.sources))
            }
        }
        return anchors
    }

    // MARK: - Rules

    private struct Rule {
        let kind: VerificationKind
        let pattern: String
        let minLength: Int
        let sources: [VerificationSourcePreference]
    }

    // Shared with LegalCitationFormatter (189) — one definition of "what is a numeral".
    private static let articleNumber = "[\(LegalCitationFormatter.numeralClass)]+"

    private static let rules: [Rule] = [
        // 法条号: 《X》（修订年）第N条（之N）（第N款）（第N项） — tolerates spaces ("《个保法》第 24 条").
        Rule(kind: .law,
             pattern: "《[^》]{1,40}》(?:[（(]\\d{4}年[^）)]{0,12}[)）])?第\\s*\(articleNumber)\\s*条(?:之\\s*\(articleNumber))?(?:第\\s*\(articleNumber)\\s*款)?(?:第\\s*[（(]?\\s*\(articleNumber)\\s*[)）]?\\s*项)?",
             minLength: 4, sources: [.govLaw, .pkulaw]),
        // 指导案例: 指导案例24号 / 指导案例第24号 — 无年份圆括号，独立规则。
        Rule(kind: .law,
             pattern: "指导案例(?:第)?\\s*\\d+\\s*号",
             minLength: 5, sources: [.pkulaw, .qwenSearch]),
        // 规范性文件号: 国发〔2007〕19号、法释〔2018〕1号 — 六角括号 〔 〕 区别于案号的圆括号（手册 §64 vs §71）.
        Rule(kind: .officialDocument,
             pattern: "[一-龥]{1,8}〔\\s*\\d{4}\\s*〕\\s*\\d+\\s*号",
             minLength: 5, sources: [.govLaw, .pkulaw]),
        // 案号: (2021)京01民终1234号 — 圆括号（含半角）; 六角括号〔〕也兜底（部分来源误用）。
        Rule(kind: .caseLaw,
             pattern: "[(（〔]\\s*\\d{4}\\s*[)）〕][^\\s，。；,.；]{2,24}?号",
             minLength: 8, sources: [.pkulaw, .qwenSearch]),
        // 标准号: GB/T 39335-2020, ISO 27001
        Rule(kind: .standard,
             pattern: "(?:GB(?:/T)?|JR/T|YD/T|ISO|IEC)\\s*\\d+(?:[\\-—.]\\d+)*",
             minLength: 4, sources: [.govLaw, .qwenSearch]),
        // 日期: 2021年1月1日 / 2021-01-01
        Rule(kind: .date,
             pattern: "\\d{4}\\s*年\\s*\\d{1,2}\\s*月\\s*\\d{1,2}\\s*日|\\d{4}-\\d{1,2}-\\d{1,2}",
             minLength: 6, sources: [.manual]),
        // 金额: 10万元 / ￥1,200.50 / 5000元
        Rule(kind: .money,
             pattern: "(?:￥|¥)\\s*\\d[\\d,]*(?:\\.\\d+)?|\\d[\\d,]*(?:\\.\\d+)?\\s*(?:万|亿)?\\s*元",
             minLength: 2, sources: [.manual]),
    ]

    // MARK: - Regex helpers

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// Collapse internal whitespace so "《个保法》第 24 条" → "《个保法》第24条".
    static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    // Longest-first so 依据 is stripped before 依/据, 参见 before 见.
    private static let docLeadIns = ["依据", "根据", "参见", "按照", "依照", "适用", "载于",
                                     "见", "据", "依", "按", "载"]

    /// Strip a common lead-in verb/particle a 文件号 regex may absorb before 机关简称
    /// (Chinese has no orthographic boundary, e.g. "依据国发〔2007〕19号" → "国发〔2007〕19号").
    static func stripLeadIn(_ s: String) -> String {
        for w in docLeadIns where s.hasPrefix(w) { return String(s.dropFirst(w.count)) }
        return s
    }
}
