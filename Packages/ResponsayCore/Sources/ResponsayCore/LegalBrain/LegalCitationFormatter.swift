import Foundation

// MARK: - 189 LegalCitationFormatter — 《法学引注手册》(2019) 体例
//
// Renders citations in the manual's form for OUTPUT (脚注草稿 / [待核] anchor display).
// The single most load-bearing rule (manual §64 vs §71), routinely confused:
//   规范性文件号 → 六角括号 〔2018〕      案号 → 圆括号 （1998）
// 行文 序数 use Arabic and 项 drops its 括号 (§61); 序数 INSIDE a law name stay verbatim
// (§61.3); 中华人民共和国 may be dropped at the OUTER level only, nested 〈…〉 keep it (§59).
//
// Foundation-only. Rules derived from the manual + 法〔2015〕137号 (案号 structure); no manual
// text is copied. This is a PRODUCER for generated 行文 — it is intentionally NOT applied
// blindly to every extracted anchor, because 原文引用 keeps 汉字 (§61.2) and in-text [待核]
// tagging matches the source span (see `VerificationAnchor.conformantLabel`).

public struct LegalCitationFormatter: Sendable {
    public init() {}

    // MARK: 法条 行文 (§59–§61)

    /// `《公司法》（2013年修正）第二十七条第二款第（三）项` → `《公司法》（2013年修正）第27条第2款第3项`.
    /// Name (and 序数 inside `《》`/`〈〉`) is verbatim; only the trailing 第…条/款/项/目 is
    /// Arabic-ized and 项 loses its parentheses.
    public func lawProse(_ raw: String) -> String {
        let s = collapse(raw)
        guard let (name, tail) = Self.splitNameAndTail(s) else { return Self.arabicizeOrdinals(s) }
        return name + Self.arabicizeOrdinals(tail)
    }

    /// Drop a leading 中华人民共和国 from the OUTER law name only (§59); nested 〈…〉 untouched.
    public func abbreviateLawName(_ raw: String) -> String {
        let s = collapse(raw)
        guard let open = s.range(of: "《") else { return s }
        let tail = s[open.upperBound...]
        guard tail.hasPrefix("中华人民共和国") else { return s }
        let cut = s.index(open.upperBound, offsetBy: "中华人民共和国".count)
        return String(s[..<open.upperBound]) + String(s[cut...])
    }

    // MARK: 案号 / 文件号 brackets (§71 vs §64)

    /// 案号 → year in fullwidth 圆括号 （ ）. Normalizes ascii / 六角 → 圆括号.
    public func caseNumber(_ raw: String) -> String {
        Self.replaceYearBracket(in: collapse(raw), open: "（", close: "）")
    }

    /// 规范性文件号 → year in 六角括号 〔 〕. Normalizes ascii / 圆括号 → 六角括号.
    public func documentNumber(_ raw: String) -> String {
        Self.replaceYearBracket(in: collapse(raw), open: "〔", close: "〕")
    }

    // MARK: numerals

    /// Chinese numeral (一/十/百/千 + 零/〇) → Int; nil if not a pure numeral. Up to 9999.
    public static func chineseToInt(_ s: String) -> Int? {
        let digit: [Character: Int] = ["〇": 0, "零": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                       "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let unit: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var total = 0, current = 0, sawAny = false
        for ch in s {
            if let d = digit[ch] { current = d; sawAny = true }
            else if let u = unit[ch] { total += (current == 0 ? 1 : current) * u; current = 0; sawAny = true }
            else { return nil }
        }
        return sawAny ? total + current : nil
    }

    static func arabic(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) { return s }
        if let n = chineseToInt(s) { return String(n) }
        return s
    }

    /// Regex character-class body for an Arabic-or-Chinese numeral. Single source of truth,
    /// shared with `FactCoordinateExtractor` (the same decision was previously written twice).
    static let numeralClass = "0-9〇零一二三四五六七八九十百千两"

    // MARK: helpers

    private func collapse(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    static func splitNameAndTail(_ s: String) -> (name: String, tail: String)? {
        guard let close = s.range(of: "》") else { return nil }
        var end = close.upperBound
        let rest = s[end...]
        if rest.hasPrefix("（"), let p = rest.range(of: "）") { end = p.upperBound }
        return (String(s[..<end]), String(s[end...]))
    }

    /// Arabic-ize `第<num>(条|款|项|目)` and `之<num>`; drop parens around 项's number.
    static func arabicizeOrdinals(_ tail: String) -> String {
        var s = tail
        s = replaceMatches(in: s, pattern: "第[（(]?([\(numeralClass)]+)[)）]?(条|款|项|目)") {
            "第" + arabic($0[0]) + $0[1]
        }
        s = replaceMatches(in: s, pattern: "之([\(numeralClass)]+)") {
            "之" + arabic($0[0])
        }
        return s
    }

    static func replaceYearBracket(in s: String, open: String, close: String) -> String {
        replaceMatches(in: s, pattern: "[（(〔]\\s*(\\d{4})\\s*[)）〕]") { open + $0[0] + close }
    }

    /// Run `pattern`, replacing each whole match with `transform(capture groups 1…n)`.
    static func replaceMatches(in text: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            var groups: [String] = []
            for i in 1..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            if let whole = Range(m.range, in: result) {
                result.replaceSubrange(whole, with: transform(groups))
            }
        }
        return result
    }
}

public extension VerificationAnchor {
    /// The 《法学引注手册》-conformant rendering of this anchor's label, for footnote / display.
    /// Non-mutating: the stored `label` stays source-matching so in-text `[待核]` tagging works.
    func conformantLabel(_ f: LegalCitationFormatter = LegalCitationFormatter()) -> String {
        switch kind {
        case .law:                                    return f.lawProse(label)
        case .caseLaw:                                return f.caseNumber(label)
        case .administrativeRule, .officialDocument:  return f.documentNumber(label)
        default:                                      return label
        }
    }
}
