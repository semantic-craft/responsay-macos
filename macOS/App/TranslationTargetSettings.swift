import Foundation
import ResponsayCore

/// The user's translation language pair (Bob model), driving direction across 听写翻译 /
/// 划词翻译 / 截图翻译:
/// - 第一语言（母语）: what foreign material is translated *into*. Default 中文.
/// - 第二语言（外语）: what 母语 is translated *into* (听写/划词翻译). Default 英语.
///
/// `secondaryLanguageKey` reuses the legacy single-target key `translationTargetLanguage`, so an
/// existing user's 听写/划词 target carries over unchanged as their 第二语言.
enum TranslationTargetSettings {
    /// Legacy single-target key — now the 第二语言（外语）. Kept so existing choices migrate silently.
    static let targetLanguageKey = "translationTargetLanguage"
    static let primaryLanguageKey = "translatePrimaryLanguage"

    static let defaultPrimary = TranslationTargetLanguage.chineseSimplified
    static let defaultSecondary = TranslationTargetLanguage.englishUS

    /// 第一语言（母语）— the language foreign material is translated into.
    static func primaryLanguage() -> TranslationTargetLanguage {
        read(primaryLanguageKey) ?? defaultPrimary
    }

    /// 第二语言（外语）— the 听写/划词翻译 target (母语 → 外语).
    static func secondaryLanguage() -> TranslationTargetLanguage {
        read(targetLanguageKey) ?? defaultSecondary
    }

    private static func read(_ key: String) -> TranslationTargetLanguage? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return TranslationTargetLanguage(rawValue: raw)
    }
}
