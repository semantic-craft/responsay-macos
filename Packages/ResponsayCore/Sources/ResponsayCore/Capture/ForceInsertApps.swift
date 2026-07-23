import Foundation

/// Apps whose accessibility **editability signal is unreliable**, but where the user is
/// overwhelmingly dictating into a real input box — so an absent/negative AX probe must NOT
/// suppress insertion with a copy pill.
///
/// This mirrors Typeless's app allow-list (its macOS `app_blacklist` "best-effort" +
/// `app_whitelist` "guaranteed-writable" — see the reverse-engineering report §9), adapted to our
/// ⌘V-paste inserter: because we paste into the focused element rather than AX-`setValue`,
/// insertion lands regardless of whether AX can *read* the field. For these apps we trust the
/// frontmost bundle over the AX role probe. The set is a **superset** of Typeless's macOS lists.
///
/// Known ceiling: dictating in a **non-input** area of one of these apps pastes into the void
/// (the text is still recoverable from history). Accepted for AX-opaque apps where the AX tree
/// can't distinguish "cursor in the box" from "cursor nowhere" anyway. Extend as more
/// AX-opaque / non-standard-AX apps surface.
///
/// NOTE: Typeless also ships URL-level lists (Google Docs / Tencent Docs best-effort, Figma
/// design whitelist). Those need browser-URL plumbing into the pill decision and are a separate
/// mechanism — not yet mirrored here.
public enum ForceInsertApps {
    public static let bundleIDs: Set<String> = [
        // — Responsay additions (the user's confirmed pain points) —
        "com.openai.codex",              // Codex desktop — non-standard AX mapping on its editor
        // Claude Desktop — Electron tree unlocked by `ElectronAXUnlock` at capture start; this
        // entry is belt-and-braces for utterances shorter than the async tree build.
        "com.anthropic.claudefordesktop",

        // — Typeless macOS app_whitelist ("guaranteed writable") —
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.tinyspeck.slackmacgap",     // Slack
        "com.apple.mail",                // Apple Mail
        "com.figma.Desktop",             // Figma
        "com.openai.atlas",              // OpenAI Atlas / ChatGPT desktop
        "com.conductor.app",             // Conductor
        "com.github.wez.wezterm",        // WezTerm

        // — Typeless macOS app_blacklist ("best-effort insertion") —
        "com.tencent.xinWeChat",         // WeChat 4.x — Qt content tree unexposed to AX
        "com.sublimetext.4",             // Sublime Text 4        ⚠︎ also in adr0014 compatDeny
        "com.microsoft.Excel",           // Excel                 ⚠︎ also in adr0014 compatDeny
        "com.kingsoft.wpsoffice.mac",    // WPS Office
        "dev.zed.Zed",                   // Zed                   ⚠︎ also in adr0014 compatDeny
    ]

    public static func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
