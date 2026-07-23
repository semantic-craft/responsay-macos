import Foundation

/// Browser **URLs** whose page is an editable web app (Google Docs, Tencent Docs, Figma) but whose
/// AX tree usually can't be read as editable — so a dictation there must NOT be suppressed with a
/// copy pill. The web-app companion to ``ForceInsertApps``: inside one browser, some pages are
/// editable and some aren't, so the decision is per-URL, not per-app.
///
/// Mirrors Typeless's `url_blacklist` ("best-effort") + `url_whitelist` ("guaranteed-writable")
/// exactly (reverse-eng report §9) — every Typeless macOS URL entry is a prefix, so this is a
/// prefix list. Only checked when the frontmost app is a recognized browser (see
/// `CaptureGateContextReader.isBrowser`).
///
/// Note: `https://docs.google.com/document/d` is also in `adr0014.securityDenyURLPrefixes`, but
/// that gate governs the **legal-brain** path only — plain dictation is unaffected, so mirroring
/// Typeless here does not weaken any privacy gate.
public enum ForceInsertURLs {
    public static let prefixes: [String] = [
        // Typeless url_blacklist (best-effort)
        "https://docs.google.com/document/d",  // Google Docs
        "https://docs.qq.com/doc/",            // Tencent Docs — documents
        "https://docs.qq.com/sheet/",          // Tencent Docs — sheets
        // Typeless url_whitelist (guaranteed writable)
        "https://www.figma.com/design/",       // Figma design files
    ]

    public static func matches(_ url: String?) -> Bool {
        guard let url else { return false }
        return prefixes.contains { url.hasPrefix($0) }
    }
}
