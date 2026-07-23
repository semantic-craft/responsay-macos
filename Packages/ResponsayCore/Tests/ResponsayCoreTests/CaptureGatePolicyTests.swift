import Testing
import Foundation
@testable import ResponsayCore

/// The fail-closed capture gate (ADR-0014 rule 2 / issues 080+052): given the
/// frontmost app + focused field + browser URL, decide whether voice capture is
/// allowed, or denied on the security axis (privacy) or the compatibility axis
/// (injection reliability). Pure policy — the macOS layer supplies the context.
@Suite struct CaptureGatePolicyTests {
    private let policy = CaptureGatePolicy.adr0014

    @Test func secureTextFieldIsAlwaysSecurityDenied() {
        // A password field denies regardless of which (otherwise-allowed) app it is in.
        let decision = policy.evaluate(
            CaptureContext(bundleID: "com.apple.TextEdit", isSecureTextField: true))
        #expect(decision == .denied(.secureTextField))
        #expect(decision.denyAxis == .security)
    }

    @Test func passwordManagerIsSecurityDenied() {
        // We deny 1Password even though Typeless whitelisted it (ADR-0014).
        let decision = policy.evaluate(CaptureContext(bundleID: "com.1password.1password"))
        #expect(decision == .denied(.sensitiveApp(bundleID: "com.1password.1password")))
        #expect(decision.denyAxis == .security)
    }

    @Test func sensitiveBrowserURLIsSecurityDenied() {
        let decision = policy.evaluate(CaptureContext(
            bundleID: "com.google.Chrome",
            url: "https://accounts.google.com/signin/v2/identifier"))
        #expect(decision == .denied(.sensitiveURL(prefix: "https://accounts.google.com")))
        #expect(decision.denyAxis == .security)
    }

    @Test func googleAccountRedirectURLIsSecurityDenied() {
        let decision = policy.evaluate(CaptureContext(
            bundleID: "com.google.Chrome",
            url: "https://myaccount.google.com/"))
        #expect(decision == .denied(.sensitiveURL(prefix: "https://myaccount.google.com")))
        #expect(decision.denyAxis == .security)
    }

    @Test func incompatibleAppIsCompatDenied() {
        let decision = policy.evaluate(CaptureContext(bundleID: "com.microsoft.Excel"))
        #expect(decision == .denied(.incompatibleApp(bundleID: "com.microsoft.Excel")))
        #expect(decision.denyAxis == .compatibility)
    }

    @Test func ordinaryAppIsAllowed() {
        #expect(policy.evaluate(CaptureContext(bundleID: "com.apple.TextEdit")).isAllowed)
        // Unknown / undeterminable frontmost app is allowed (capture is the default
        // unless a surface is positively known sensitive).
        #expect(policy.evaluate(CaptureContext(bundleID: nil)).isAllowed)
    }

    @Test func securityChecksTakePrecedenceOverCompatibility() {
        // A secure field inside a compat-denied app must deny on SECURITY, never
        // surface a mere compatibility reason (ADR-0014: a compat entry can never
        // shadow a privacy gate).
        let secureInCompatApp = policy.evaluate(
            CaptureContext(bundleID: "com.microsoft.Excel", isSecureTextField: true))
        #expect(secureInCompatApp == .denied(.secureTextField))
        #expect(secureInCompatApp.denyAxis == .security)
    }

    @Test func registerDomainSuppressedOnSecureField() {
        // 463/#052 — the browser host feeds the register classifier, but never from a secure field.
        #expect(CaptureContext(url: "mail.google.com").registerDomain == "mail.google.com")
        #expect(CaptureContext(isSecureTextField: true, url: "mybank.com/login").registerDomain == nil)
    }
}
