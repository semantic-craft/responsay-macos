import Foundation

/// Target-language choice for **截图翻译** (snap & translate). `.auto` follows the Bob model
/// using the user's 第一语言（母语）/ 第二语言（外语） pair: a foreign screenshot → 第一语言;
/// a screenshot already in 第一语言 → 第二语言. So the common case — snap an English page with
/// 第一=中文 — gives Chinese with no per-shot setting; the explicit cases pin one fixed language.
public enum SnapTranslateTarget: String, CaseIterable, Identifiable, Sendable {
    /// Auto-direction via the 第一/第二语言 pair (外文 → 母语; 母语 → 外语).
    case auto
    case chinese
    case english
    case german
    case japanese

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "自动（外文→母语）"
        case .chinese: "中文"
        case .english: "英语"
        case .german: "德语"
        case .japanese: "日语"
        }
    }

    /// The concrete target language to translate `text` into, given the user's language pair.
    /// `.auto` = Bob's rule (原文译向 `primary`；若原文已是 `primary` → `secondary`), with
    /// "原文 is `primary`" detected by the Chinese (CJK) heuristic — exact when `primary` is
    /// Chinese (the default + dominant case), best-effort otherwise.
    public func resolved(
        for text: String,
        primary: TranslationTargetLanguage,
        secondary: TranslationTargetLanguage
    ) -> TranslationTargetLanguage {
        switch self {
        case .auto:
            let textIsChinese = Self.isMostlyChinese(text)
            // primary == 中文: Chinese source IS the primary → secondary; else → primary.
            // primary ≠ 中文: Chinese source is NOT the primary → primary; non-Chinese (assumed
            // primary) → secondary.
            return primary == .chineseSimplified
                ? (textIsChinese ? secondary : primary)
                : (textIsChinese ? primary : secondary)
        case .chinese: return .chineseSimplified
        case .english: return .englishUS
        case .german: return .german
        case .japanese: return .japanese
        }
    }

    /// Heuristic: is the text predominantly Han characters? Counts CJK ideographs vs. Latin
    /// letters and ignores everything else (digits, punctuation, whitespace), so a mixed
    /// English+number snippet still reads as non-Chinese → translate to Chinese. Ties favour
    /// Chinese-source (→ English) since a Chinese user snapping their own text wants the foreign
    /// rendering. No letters of either kind → treat as non-Chinese (→ Chinese).
    static func isMostlyChinese(_ text: String) -> Bool {
        var han = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)      // CJK Unified Ideographs
                || (0x3400...0x4DBF).contains(v)  // Extension A
                || (0xF900...0xFAFF).contains(v) {// Compatibility Ideographs
                han += 1
            } else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
                latin += 1
            }
        }
        guard han + latin > 0 else { return false }
        return han >= latin
    }
}
