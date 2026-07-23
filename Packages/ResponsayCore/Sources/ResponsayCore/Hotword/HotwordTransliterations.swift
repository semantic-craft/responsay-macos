import Foundation

/// Curated Chinese-transliteration readings for common ASCII technical terms (#469).
///
/// When an ASR mishears a spoken English word as its Chinese transliteration (脱肯 for
/// "Token", 思可瑞特 for "Secret"), the hard-match pass restores the ASCII spelling — but only
/// for a **registered** hotword (ADR-0011 anchoring) and only via these explicit readings.
/// We deliberately avoid blind cross-script phonetic matching of *all* ASCII terms, which would
/// over-correct short words (API / SDK): a term is transliteration-matched only if it appears
/// here. This is the deterministic safety net for the non-LLM path; the "意图成稿" LLM already
/// handles transliteration on its own path.
///
/// Keys are normalized (lowercased, ASCII `[a-z0-9]`) to match `HotwordHardMatch`'s term keys.
/// Each value lists plausible Chinese readings; toneless pinyin already collapses homophone
/// variants (脱肯 / 拓肯 / 托肯 → tuo ken), so only genuinely distinct readings need listing. Keep
/// readings ≥2 syllables and distinctive — short/ambiguous transliterations are intentionally omitted.
///
/// User-attachable per-term readings (issue 469 "Option A") are a deferred follow-up; this is
/// the curated built-in table ("Option B").
public enum HotwordTransliterations {
    public static let readings: [String: [String]] = [
        "token": ["脱肯"],
        "secret": ["思可瑞特"],
        "webhook": ["微虎克"],
        "cursor": ["克瑟尔"],
        "prompt": ["普弱姆普特"],
    ]

    /// The Chinese readings registered for a normalized ASCII key, or `[]` if none.
    static func readings(forKey key: String) -> [String] {
        readings[key] ?? []
    }
}
