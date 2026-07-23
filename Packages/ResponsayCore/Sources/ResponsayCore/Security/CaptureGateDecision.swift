import Foundation

/// Why capture was blocked. The axis is derived from the reason so a
/// compatibility fix can never silently weaken a privacy (security) gate.
public enum CaptureDenyReason: Sendable, Equatable {
    /// A secure/password text field is focused.
    case secureTextField
    /// The frontmost app is on the privacy deny list.
    case sensitiveApp(bundleID: String)
    /// The frontmost browser URL matches a privacy deny prefix.
    case sensitiveURL(prefix: String)
    /// The frontmost app is a known-incompatible injection target.
    case incompatibleApp(bundleID: String)
}

/// Two distinct deny axes (ADR-0014 rule 2): security = privacy (never
/// transcribe), compatibility = injection reliability only.
public enum CaptureDenyAxis: Sendable, Equatable {
    case security
    case compatibility
}

public extension CaptureDenyReason {
    var axis: CaptureDenyAxis {
        switch self {
        case .secureTextField, .sensitiveApp, .sensitiveURL:
            return .security
        case .incompatibleApp:
            return .compatibility
        }
    }
}

/// The decision the capture gate returns for a given context.
public enum CaptureGateDecision: Sendable, Equatable {
    case allowed
    case denied(CaptureDenyReason)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// The axis of a denial, or `nil` when allowed.
    public var denyAxis: CaptureDenyAxis? {
        if case let .denied(reason) = self { return reason.axis }
        return nil
    }
}

/// What the macOS layer knows about the current capture target.
public struct CaptureContext: Sendable, Equatable {
    public let bundleID: String?
    public let isSecureTextField: Bool
    public let url: String?

    public init(bundleID: String? = nil, isSecureTextField: Bool = false, url: String? = nil) {
        self.bundleID = bundleID
        self.isSecureTextField = isSecureTextField
        self.url = url
    }

    /// 463 — the browser-tab host fed to the register classifier, suppressed on a secure field so
    /// #052 (never read URL in password/sensitive contexts) holds at the source.
    public var registerDomain: String? { isSecureTextField ? nil : url }
}
