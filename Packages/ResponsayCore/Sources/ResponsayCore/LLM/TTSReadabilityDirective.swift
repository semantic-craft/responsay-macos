import Foundation

/// Shared speakability directive (#427) injected ONLY into the 地道英文 (express) prompt: its
/// `idiomatic` output is read aloud by TTS (讲解卡 🔊 + direct-write → TTS), so it must be plain,
/// spoken-natural text. The 🔊 button reads `activeIdiomatic`, which becomes the *selected*
/// `alternatives` entry when the user taps one (#479) — so the alternatives are read aloud too and
/// carry the same plain-spoken constraints. Deliberately NOT used by rewrite / polish / translate /
/// legal — those are not for reading aloud, or require structured / faithful presentation.
enum TTSReadabilityDirective {
    static let speakable = [
        "Speakability (the \"idiomatic\" sentence — and any \"alternatives\", since the user can pick one to play — are read aloud by TTS):",
        "- Write \"idiomatic\" and every \"alternatives\" entry as plain, spoken-natural text a person would actually say out loud.",
        "- No markdown, bullets, code, URLs, emoji, parentheticals, or document symbols in \"idiomatic\" or any \"alternatives\".",
        "- Prefer short, easy-to-say sentences that flow when spoken; avoid clause pile-ups and written-prose syntax.",
    ].joined(separator: "\n")
}
