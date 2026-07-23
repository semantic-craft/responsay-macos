import Foundation

/// #5 reduced: the "how does text reach the app" decision, centralized as two pure rules so the
/// route (copy-pill vs insert vs no-op) and the mechanism order (clipboard vs keystroke under Secure
/// Input) are testable in one place instead of being buried across `apply()`, `CaptureResultInserter`,
/// and `CGEventTextInserter`. Stays pure — macOS signals enter as plain `Bool` (no CGEvent here).
public enum InsertionRoute: Equatable, Sendable { case copyPill, insert, skip }

public enum InsertionMethod: Equatable, Sendable { case clipboard, keystroke }

public enum InsertionStrategyResolver {
    /// Route rule — copy-pill vs insert vs no-op. Platform-agnostic.
    /// `isEditableTarget` is an `@autoclosure` returning `Bool?`, evaluated only on the
    /// `.insertImmediately` + `hasText` path — matching HEAD's short-circuit so the AX focus read never
    /// runs for `.replaceSelection` / `.copyOnly` / `.noInsert`. nil (no provider / headless) never
    /// copy-pills (nil ≠ false).
    public static func route(policy: InsertPolicy, isEditableTarget: @autoclosure () -> Bool?, hasText: Bool) -> InsertionRoute {
        switch policy {
        case .copyOnly, .noInsert:
            return .skip
        case .replaceSelection:
            return .insert
        case .insertImmediately:
            if hasText, isEditableTarget() == false { return .copyPill }
            return .insert
        }
    }

    /// Mechanism order — try clipboard (⌘V) first; keystroke only when Secure Input is off (synthetic
    /// key events are swallowed under Secure Input). Matches HEAD's CGEventTextInserter branch.
    public static func mechanismOrder(isSecureInputActive: Bool) -> [InsertionMethod] {
        isSecureInputActive ? [.clipboard] : [.clipboard, .keystroke]
    }
}
