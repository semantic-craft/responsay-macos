import Testing
@testable import ResponsayCore

// Safety fence: LLM/search-returned 核验 URLs must not be clickable unless they
// are plain http(s) web links.
struct ExternalLinkPolicyTests {
    @Test func allowsPlainWebURLs() {
        #expect(ExternalLinkPolicy.safeWebURL("https://flk.npc.gov.cn/detail2.html?id=1") != nil)
        #expect(ExternalLinkPolicy.safeWebURL("http://example.com/path") != nil)
        #expect(ExternalLinkPolicy.safeWebURL("HTTPS://Example.com") != nil)   // scheme case-insensitive
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(ExternalLinkPolicy.safeWebURL("  https://example.com  ") != nil)
    }

    @Test func rejectsDangerousSchemes() {
        #expect(ExternalLinkPolicy.safeWebURL("javascript:alert(1)") == nil)
        #expect(ExternalLinkPolicy.safeWebURL("file:///etc/passwd") == nil)
        #expect(ExternalLinkPolicy.safeWebURL("data:text/html,<script>x</script>") == nil)
        #expect(ExternalLinkPolicy.safeWebURL("ftp://example.com/x") == nil)
        #expect(ExternalLinkPolicy.safeWebURL("someapp://do-something") == nil)   // custom app scheme
    }

    @Test func rejectsSchemelessOrHostless() {
        #expect(ExternalLinkPolicy.safeWebURL("example.com/foo") == nil)          // no explicit scheme
        #expect(ExternalLinkPolicy.safeWebURL("https://") == nil)                 // no host
        #expect(ExternalLinkPolicy.safeWebURL("") == nil)
        #expect(ExternalLinkPolicy.safeWebURL("   ") == nil)
    }

    @Test func rejectsUserinfoPhishing() {
        // Displayed text looks like google.com, but the real host is evil.com.
        #expect(ExternalLinkPolicy.safeWebURL("https://google.com@evil.com/login") == nil)
    }
}
