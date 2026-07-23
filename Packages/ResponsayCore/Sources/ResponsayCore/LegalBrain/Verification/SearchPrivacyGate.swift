import Foundation

// MARK: - Privacy gate for LLM search verification

public enum SearchPrivacyGate {

    public enum SearchPermission: Sendable, Equatable {
        case allowed
        case needsConfirm
        case disabled
    }

    public static func permission(for route: ModelRoute) -> SearchPermission {
        switch route {
        case .cloudAllowed:              return .allowed
        case .cloudRequiresUserConfirm:  return .needsConfirm
        case .localOnly, .blocked:       return .disabled
        }
    }

    public static func disabledReason(for route: ModelRoute) -> String? {
        switch route {
        case .localOnly:
            return "本地模式不支持联网核验，请使用链接手动查"
        case .blocked:
            return "安全输入框 / 敏感应用：联网核验已阻止"
        case .cloudAllowed, .cloudRequiresUserConfirm:
            return nil
        }
    }
}

public extension SearchPrivacyGate.SearchPermission {
    var isSearchEnabled: Bool {
        self != .disabled
    }

    var requiresConfirmation: Bool {
        self == .needsConfirm
    }
}
