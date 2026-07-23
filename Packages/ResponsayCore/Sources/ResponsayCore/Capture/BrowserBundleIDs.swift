import Foundation

/// Chromium- and Gecko-family browsers whose **web-content accessibility tree is built lazily**:
/// until an assistive client sets `AXEnhancedUserInterface` on the app, the focused web
/// `<input>` / `<textarea>` is invisible to accessibility (`kAXFocusedUIElementAttribute` resolves
/// to an opaque container or nothing), so `CaptureGateContextReader.hasEditableFocus` finds no
/// settable field and every web field wrongly fires a copy pill (CHROME-WEB-AX-001 — reported on
/// Gemini / Google 搜索 / 豆瓣, all inside Chrome).
///
/// Setting `AXEnhancedUserInterface` is the switch Typeless uses (its native
/// `setFocusedWindowEnhancedUserInterface`, reverse-eng report §4.1 / §11.3) to make the web tree
/// materialize. It is scoped to *these* bundles because the attribute is the "assistive tech is
/// active" signal and can perturb layout in some **non-browser** AppKit apps — so we only set it
/// where a hidden web tree is the known failure mode. Safari / WebKit is intentionally excluded:
/// it exposes its web tree without the attribute.
public enum BrowserBundleIDs {
    /// Bundles that need `AXEnhancedUserInterface` to expose their web-content AX tree.
    public static let webAXTreeUnlock: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",   // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
        "ai.perplexity.comet",
        "com.duckduckgo.macos.browser",
        "com.kagi.kagimacOS",
        "com.openai.atlas",             // ChatGPT / Atlas (Chromium)
        "org.mozilla.firefox",
        "org.mozilla.nightly",
    ]

    /// Whether this app needs its web-content AX tree unlocked via `AXEnhancedUserInterface`.
    public static func needsWebAXTreeUnlock(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return webAXTreeUnlock.contains(bundleID)
    }
}
