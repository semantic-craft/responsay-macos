import Foundation

// MARK: - 112 LegalBrainEnabled feature flag
//
// Gates the whole legal subsystem so it ships behind a switch with clean failure
// isolation from the dictation product. Default = on for internal testers (DEBUG),
// off for release until ready. The macOS layer reads a stored override from
// UserDefaults and resolves it through here; the flag TYPE + default live in core
// so the gating logic is testable.

public struct LegalBrainFlag: Sendable, Equatable {
    /// UserDefaults key for the optional stored override.
    public static let defaultsKey = "legalBrainEnabled"

    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// On for internal testers, off for release — flip by build configuration.
    public static var defaultEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Resolve from a stored override (`nil` → use the build default).
    public static func resolve(stored: Bool?) -> LegalBrainFlag {
        LegalBrainFlag(isEnabled: stored ?? defaultEnabled)
    }
}
