import Foundation

/// Fail-closed capture gate (ADR-0014 rule 2). Evaluates a ``CaptureContext``
/// against two distinct deny axes; security checks run first so a compatibility
/// entry can never shadow a privacy denial.
public struct CaptureGatePolicy: Sendable {
    private let securityDenyBundleIDs: Set<String>
    private let compatDenyBundleIDs: Set<String>
    private let securityDenyURLPrefixes: [String]

    public init(
        securityDenyBundleIDs: Set<String>,
        compatDenyBundleIDs: Set<String>,
        securityDenyURLPrefixes: [String]
    ) {
        self.securityDenyBundleIDs = securityDenyBundleIDs
        self.compatDenyBundleIDs = compatDenyBundleIDs
        self.securityDenyURLPrefixes = securityDenyURLPrefixes
    }

    public func evaluate(_ context: CaptureContext) -> CaptureGateDecision {
        // 1. A secure field denies regardless of app — the fail-closed core.
        if context.isSecureTextField {
            return .denied(.secureTextField)
        }
        if let bundleID = context.bundleID, securityDenyBundleIDs.contains(bundleID) {
            return .denied(.sensitiveApp(bundleID: bundleID))
        }
        if let url = context.url,
           let prefix = securityDenyURLPrefixes.first(where: url.hasPrefix) {
            return .denied(.sensitiveURL(prefix: prefix))
        }
        // Compatibility checks run last so they can never shadow a security denial.
        if let bundleID = context.bundleID, compatDenyBundleIDs.contains(bundleID) {
            return .denied(.incompatibleApp(bundleID: bundleID))
        }
        return .allowed
    }
}

public extension CaptureGatePolicy {
    /// The default policy seeded with the ADR-0014 deny lists.
    static let adr0014 = CaptureGatePolicy(
        securityDenyBundleIDs: [
            "com.apple.loginwindow",
            "com.apple.ScreenSaver.Engine",
            "com.apple.keychainaccess",
            "com.agilebits.onepassword",   // 1Password 7
            "com.1password.1password",     // 1Password 8
            "com.lastpass.LastPass",
            "com.bitwarden.desktop"
        ],
        compatDenyBundleIDs: [
            "com.microsoft.Excel",
            "dev.zed.Zed",
            "com.sublimetext.4"
        ],
        securityDenyURLPrefixes: [
            "chrome://",
            "about:",
            "https://accounts.google.com",
            "https://myaccount.google.com",
            "https://docs.google.com/document/d"
        ])
}
