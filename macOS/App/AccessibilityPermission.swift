import AppKit
import ApplicationServices
import ResponsayCore

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static let guidance = "未获辅助功能权限。请在 系统设置 › 隐私与安全性 › 辅助功能 中开启 \(AppBrand.displayName)。"

    @discardableResult
    static func promptIfNeeded() -> Bool {
        guard !isTrusted else { return true }
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    static func requestFromUserAction() -> Bool {
        let trusted = promptIfNeeded()
        if !trusted { openSystemSettings() }
        return trusted
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
