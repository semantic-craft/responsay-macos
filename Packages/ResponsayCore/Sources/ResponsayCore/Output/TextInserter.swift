import Foundation

/// 把文本送进当前聚焦的 App 输入框。
@MainActor
public protocol TextInserter: AnyObject {
    func insert(_ text: String) async throws
}

public enum InsertError: LocalizedError {
    case notAuthorized          // 辅助功能未授权
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未获辅助功能权限。请在 系统设置 › 隐私与安全性 › 辅助功能 中开启 \(AppBrand.displayName)。"
        case .failed(let m): return m
        }
    }
}
