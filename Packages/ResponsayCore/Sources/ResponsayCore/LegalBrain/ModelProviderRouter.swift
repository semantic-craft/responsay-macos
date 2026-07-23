import Foundation

// MARK: - 106 / v0.2 §14 ModelProviderRouter
//
// Adds a `purpose` axis on top of the **built** `ModelRoute` (issue 110's
// privacy decision). No parallel PrivacyMode/route enum: privacy stays `ModelRoute`;
// `purpose` only ever *downgrades* (never upgrades) the privacy-derived base route.
// `localSensitive` is forced local; `localOnly` base is never escalated to cloud.

/// What a model call is for. Drives provider/tier selection alongside privacy.
public enum ModelPurpose: String, Codable, Sendable, CaseIterable {
    case fastPolish          // quick, low-stakes rewrite
    case legalSkill          // structured legal reasoning (anchor skills)
    case legalVerification   // fact / source checking (Q3 backend search)
    case localSensitive      // privileged / confidential → must stay on-device
}

public struct ModelProviderRouter: Sendable {
    public init() {}

    /// Resolve the effective route for a `purpose` given the privacy-derived `baseRoute`.
    /// `localSensitive` always forces `.localOnly`; a `.localOnly` or `.blocked` base is
    /// never upgraded; otherwise the base route is honored verbatim. This is the single
    /// place that guarantees "localOnly never hits cloud" (acceptance §3, ADR-0014).
    public func route(purpose: ModelPurpose, baseRoute: ModelRoute) -> ModelRoute {
        if purpose == .localSensitive { return .localOnly }
        switch baseRoute {
        case .blocked:    return .blocked
        case .localOnly:  return .localOnly          // privacy floor — never escalate
        case .cloudAllowed, .cloudRequiresUserConfirm:
            return baseRoute
        }
    }

    /// Whether the resolved route permits any cloud call at all.
    public func allowsCloud(_ route: ModelRoute) -> Bool {
        switch route {
        case .cloudAllowed, .cloudRequiresUserConfirm: return true
        case .localOnly, .blocked: return false
        }
    }
}
