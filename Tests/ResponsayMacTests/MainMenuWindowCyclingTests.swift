import AppKit
import XCTest
@testable import ResponsayMac

@MainActor
final class MainMenuWindowCyclingTests: XCTestCase {
    func testCommandBacktickCyclesToTheNextKeyableWindow() async throws {
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        // The test host is the app itself, so its own windows join `NSApp.orderedWindows` and
        // therefore the cycle — on a runner without the permissions the app asks for, 「补齐权限」
        // is up from launch and ⌘` lands there instead of wrapping to the first fixture. Order
        // the host's windows out for the duration so the assertions describe the fixtures rather
        // than whatever the machine running the suite happens to be showing.
        let hostWindows = keyableWindows()
        hostWindows.forEach { $0.orderOut(nil) }
        let first = makeWindow(title: "First test window", level: .floating)
        let second = makeWindow(title: "Second test window", level: .normal)
        defer {
            first.close()
            second.close()
            hostWindows.forEach { $0.orderFront(nil) }
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
        }

        let mainMenu = MainMenuBuilder.build()
        NSApp.mainMenu = mainMenu
        let windowMenu = try XCTUnwrap(mainMenu.items.first(where: { $0.title == "窗口" })?.submenu)
        let cycleItem = try XCTUnwrap(windowMenu.items.first(where: {
            $0.keyEquivalent == "`" && $0.keyEquivalentModifierMask == [.command]
        }))
        let action = try XCTUnwrap(cycleItem.action)

        NSApp.activate(ignoringOtherApps: true)
        second.orderFront(nil)
        first.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(first.isKeyWindow, "the first fixture window should begin as key")

        XCTAssertTrue(NSApp.sendAction(action, to: cycleItem.target, from: cycleItem))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(second.isKeyWindow, "Command-Backtick should make the next fixture window key")

        XCTAssertEqual(keyableWindows().count, 2, "only the two fixtures should be in the cycle")

        XCTAssertTrue(NSApp.sendAction(action, to: cycleItem.target, from: cycleItem))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(first.isKeyWindow, "a second Command-Backtick should cycle back to the first window")
    }

    /// The same candidate set `AppMenuActions.cycleWindows` builds — visible, un-miniaturized,
    /// key-capable windows, in front-to-back order.
    private func keyableWindows() -> [NSWindow] {
        NSApp.orderedWindows.filter { $0.isVisible && !$0.isMiniaturized && $0.canBecomeKey }
    }

    private func makeWindow(title: String, level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 320, height: 200),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.level = level
        window.isReleasedWhenClosed = false
        return window
    }
}
