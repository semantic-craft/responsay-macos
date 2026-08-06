import AppKit
import XCTest
@testable import ResponsayMac

@MainActor
final class MainMenuWindowCyclingTests: XCTestCase {
    func testCommandBacktickCyclesToTheNextKeyableWindow() async throws {
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        let first = makeWindow(title: "First test window", level: .floating)
        let second = makeWindow(title: "Second test window", level: .normal)
        defer {
            first.close()
            second.close()
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

        XCTAssertTrue(NSApp.sendAction(action, to: cycleItem.target, from: cycleItem))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(first.isKeyWindow, "a second Command-Backtick should cycle back to the first window")
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
