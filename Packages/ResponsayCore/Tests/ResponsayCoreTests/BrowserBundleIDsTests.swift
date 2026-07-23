import Testing
@testable import ResponsayCore

// The web-AX-tree-unlock list must cover the Chromium/Gecko browsers that hide their web content
// from accessibility until `AXEnhancedUserInterface` is set (CHROME-WEB-AX-001). A test here mainly
// guards against bundle-ID typos and against Safari/non-browsers accidentally slipping in (setting
// the attribute on those is either useless or perturbs layout).

@Test func browserUnlock_coversChromiumAndGeckoBrowsers() {
    #expect(BrowserBundleIDs.needsWebAXTreeUnlock("com.google.Chrome"))       // the reported case
    #expect(BrowserBundleIDs.needsWebAXTreeUnlock("com.google.Chrome.canary"))
    #expect(BrowserBundleIDs.needsWebAXTreeUnlock("com.microsoft.edgemac"))
    #expect(BrowserBundleIDs.needsWebAXTreeUnlock("com.brave.Browser"))
    #expect(BrowserBundleIDs.needsWebAXTreeUnlock("org.mozilla.firefox"))
}

@Test func browserUnlock_excludesSafariAndNonBrowsers() {
    #expect(!BrowserBundleIDs.needsWebAXTreeUnlock("com.apple.Safari"))          // WebKit tree always on
    #expect(!BrowserBundleIDs.needsWebAXTreeUnlock("com.apple.TextEdit"))
    #expect(!BrowserBundleIDs.needsWebAXTreeUnlock("com.tencent.xinWeChat"))
    #expect(!BrowserBundleIDs.needsWebAXTreeUnlock(nil))
}
