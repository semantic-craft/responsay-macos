import Testing
@testable import ResponsayCore

// The force-insert allow-list must cover the user's confirmed pain points and be a superset of
// Typeless's macOS app lists. A test here mainly guards against bundle-ID typos.

@Test func forceInsert_coversConfirmedApps() {
    #expect(ForceInsertApps.contains("com.tencent.xinWeChat"))  // WeChat
    #expect(ForceInsertApps.contains("com.openai.codex"))       // Codex desktop
    #expect(ForceInsertApps.contains("com.anthropic.claudefordesktop"))  // Claude Desktop
}

@Test func forceInsert_isSupersetOfTypelessMacOSLists() {
    let typelessMacOS: Set<String> = [
        // whitelist
        "com.todesktop.230313mzl4w4u92", "com.tinyspeck.slackmacgap", "com.apple.mail",
        "com.figma.Desktop", "com.openai.atlas", "com.conductor.app", "com.github.wez.wezterm",
        // blacklist
        "com.sublimetext.4", "com.tencent.xinWeChat", "com.microsoft.Excel",
        "com.kingsoft.wpsoffice.mac", "dev.zed.Zed",
    ]
    #expect(typelessMacOS.isSubset(of: ForceInsertApps.bundleIDs))
}

@Test func forceInsert_ignoresUnknownAndNil() {
    #expect(!ForceInsertApps.contains("com.apple.finder"))
    #expect(!ForceInsertApps.contains(nil))
}

// URL allow-list — must match Typeless's macOS url lists exactly (prefix match).

@Test func forceInsertURL_matchesTypelessEditableWebApps() {
    #expect(ForceInsertURLs.matches("https://docs.google.com/document/d/abc123/edit"))
    #expect(ForceInsertURLs.matches("https://docs.qq.com/doc/xyz"))
    #expect(ForceInsertURLs.matches("https://docs.qq.com/sheet/xyz"))
    #expect(ForceInsertURLs.matches("https://www.figma.com/design/FILEKEY/Name"))
}

@Test func forceInsertURL_ignoresReadOnlyAndNil() {
    #expect(!ForceInsertURLs.matches("https://docs.google.com/spreadsheets/d/abc"))  // not in list
    #expect(!ForceInsertURLs.matches("https://news.ycombinator.com"))
    #expect(!ForceInsertURLs.matches(nil))
}
