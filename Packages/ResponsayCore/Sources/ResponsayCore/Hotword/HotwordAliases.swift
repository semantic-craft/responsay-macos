import Foundation

/// Curated cross-form **aliases** for a registered hotword (#500 S2) — the general counterpart to
/// the ASCII-only transliteration table (#469). Maps a canonical hotword spelling to alternate
/// **CJK surfaces** an ASR routinely produces that the #465 fuzzy-pinyin pass can NOT reach because
/// the drift is across a non-confusable sound (e.g. 茨 cí ↔ 兹 zī: z/c is not a standard Mandarin
/// fuzzy pair, so 拉伦兹 never snaps to 拉伦茨 phonetically — only an explicit alias bridges it).
///
/// Anchored exactly like transliterations (ADR-0011): an alias only fires when its canonical is a
/// **registered, user-provenance** hotword (seeds stay exact-only, #470). The proximity blacklist
/// (`HotwordHardMatch.protectedSurfaces`) is what keeps an aggressive alias from eating a common
/// word — alias and blacklist are the two halves of the `HaujetZhao/asr-hotword` precision design.
///
/// This is a small curated seed, NOT the primary alias source: the **auto-learn flywheel** is —
/// a user's one-time correction becomes a learned term the fuzzy pass then snaps. We do NOT add a
/// dead per-term `pronunciation`/alias field (the opentypeless anti-pattern: stored, never read);
/// every entry here actually drives matching. Surfaces must be ≥2-syllable pure-CJK and distinctive.
public enum HotwordAliases {
    /// canonical spelling → alternate CJK surfaces. Keep entries to genuine non-homophone
    /// misrecognitions the fuzzy pass misses; homophone variants need no entry (the pinyin pass
    /// already collapses them).
    public static let table: [String: [String]] = [
        "拉伦茨": ["拉伦兹"],   // Karl Larenz — 茨 cí misheard as 兹 zī (z/c, not a fuzzy pair)
    ]

    /// The alternate CJK surfaces registered for a canonical hotword spelling, or `[]` if none.
    static func aliases(forCanonical canonical: String) -> [String] {
        table[canonical] ?? []
    }
}
