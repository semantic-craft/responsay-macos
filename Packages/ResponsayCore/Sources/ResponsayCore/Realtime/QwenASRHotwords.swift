import Foundation

/// 即时热词 (`vocabulary`) rules shared by every 百炼 ASR surface that accepts them.
///
/// Scope, straight from the docs: 即时热词 is supported by exactly three models —
/// `qwen-audio-3.0-asr-flash-streaming` (the only realtime one),
/// `qwen-audio-3.0-asr-flash-filetrans` and `qwen-audio-3.0-asr-flash`. Fun-ASR-Realtime and
/// Fun-ASR-Flash share their endpoints but are not on that list.
///
/// Measured 2026-08-02 against the live service: sending `vocabulary` to `fun-asr-realtime` is
/// **accepted, not rejected** — so this gate is not preventing an error today; the field is
/// presumably ignored. It is kept because the docs scope the field to the three models above, and
/// a silently-ignored field is a weaker guarantee than a documented one. The same run also showed
/// the field genuinely works where it IS supported: identical audio through
/// `qwen-audio-3.0-asr-flash-streaming` transcribed 「法研」 with `vocabulary` off and 「法言」 with it
/// on, the rest of the sentence unchanged.
public enum QwenASRHotwords {
    /// Weight on the documented [1, 5] scale. 4 = 「明显偏好（推荐）」, which the tuning doc calls the
    /// best starting value; 5 is 「强制偏好」 and it warns that too high a weight makes
    /// similar-sounding words get misrecognised AS the hotword — a bad trade for a general
    /// dictation 词典. 50 (超级热词) is likewise avoided: caps at 50 words, recall over precision.
    public static let weight = 4

    /// Build the `vocabulary` map, dropping terms the model would reject or ignore.
    public static func vocabulary(from hotwords: [String], model: String) -> [String: Int] {
        guard supportsInstantVocabulary(model: model) else { return [:] }
        var result: [String: Int] = [:]
        for term in hotwords {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValid(cleaned) else { continue }
            result[cleaned] = weight
        }
        return result
    }

    /// 热词文本规范: a term carrying any non-ASCII character may total at most 15 characters;
    /// a pure-ASCII term at most 7 space-separated segments. The 词典 lets a user save an
    /// 80-character entry, so over-long terms are dropped here rather than sent to be ignored
    /// (or to jeopardise the whole `vocabulary` object).
    public static func isValid(_ term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if term.allSatisfy(\.isASCII) {
            return term.split(separator: " ").count <= 7
        }
        return term.count <= 15
    }

    public static func supportsInstantVocabulary(model: String) -> Bool {
        model.lowercased().hasPrefix("qwen-audio-3.0-asr-flash")
    }

    /// The capture locale code ("zh" / "en") as a documented `language_hints` value. Anything else
    /// is dropped so the model auto-detects rather than being pinned to an unknown code.
    public static func languageHint(_ language: String) -> String? {
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["zh", "en"].contains(code) ? code : nil
    }

    /// Product locale → official `language_hints`. Qwen-Audio 3.0 accepts multiple hints;
    /// Fun-ASR-Realtime accepts only the first, so mixed mode degrades to Chinese there.
    public static func languageHints(for locale: CaptureLocale, model: String) -> [String] {
        let requested: [String]
        switch locale {
        case .automatic: requested = []
        case .english: requested = ["en"]
        case .chinese: requested = ["zh"]
        case .mixed: requested = ["zh", "en"]
        }
        return model.lowercased().hasPrefix("qwen-audio-3.0")
            ? requested
            : Array(requested.prefix(1))
    }
}
