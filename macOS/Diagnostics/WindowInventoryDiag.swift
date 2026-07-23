import AppKit
import OSLog

/// #574 — a content-free map of every window this process owns, logged at the moment the
/// display-cycle crashes have struck (intent insert success). AppKit's DisplayCycle faults
/// name their window as `identifier NNNN`, which IS `windowNumber` — this inventory turns a
/// post-mortem identifier into a window class and size in one grep. Two sources: NSApp.windows
/// (has class names) and the window server (catches framework windows AppKit hides).
@MainActor
enum WindowInventoryDiag {
    private static let logger = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "window-inventory")

    static func log(moment: String) {
        for window in NSApp.windows {
            logger.info("""
                \(moment, privacy: .public) app window=\(window.windowNumber) \
                class=\(String(describing: type(of: window)), privacy: .public) \
                w=\(Int(window.frame.width)) h=\(Int(window.frame.height)) \
                visible=\(window.isVisible)
                """)
        }
        let options = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        for entry in list where (entry[kCGWindowOwnerPID as String] as? Int32) == pid {
            let number = entry[kCGWindowNumber as String] as? Int ?? -1
            let bounds = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? Double).map { Int($0) } ?? -1
            let height = (bounds["Height"] as? Double).map { Int($0) } ?? -1
            logger.info("""
                \(moment, privacy: .public) server window=\(number) w=\(width) h=\(height)
                """)
        }
    }
}
