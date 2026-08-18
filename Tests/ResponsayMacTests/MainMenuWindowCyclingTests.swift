import AppKit
import XCTest
@testable import ResponsayMac

@MainActor
final class MainMenuWindowCyclingTests: XCTestCase {
    func testCommandBacktickTargetsCycleActionAndWrapsCandidateOrder() throws {
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        defer {
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
        }

        let mainMenu = MainMenuBuilder.build()
        NSApp.mainMenu = mainMenu
        let windowMenu = try XCTUnwrap(mainMenu.items.first(where: { $0.title == "窗口" })?.submenu)
        let cycleItem = try XCTUnwrap(windowMenu.items.first(where: {
            $0.keyEquivalent == "`" && $0.keyEquivalentModifierMask == [.command]
        }))
        XCTAssertEqual(cycleItem.action, #selector(AppMenuActions.cycleWindows(_:)))
        XCTAssertTrue(cycleItem.target === AppMenuActions.shared)

        let first = makeWindow(title: "First test window")
        let hidden = makeWindow(title: "Hidden test window", isVisible: false)
        let minimized = makeWindow(title: "Minimized test window", isMiniaturized: true)
        let nonKeyable = makeWindow(title: "Non-keyable test window", canBecomeKey: false)
        let second = makeWindow(title: "Second test window")
        let orderedWindows = [first, hidden, minimized, nonKeyable, second]
        defer { orderedWindows.forEach { $0.close() } }
        var keyWindow: NSWindow? = first
        var activated: [NSWindow] = []
        let actions = AppMenuActions(
            orderedWindows: { orderedWindows },
            keyWindow: { keyWindow },
            activateWindow: { window, _ in
                activated.append(window)
                keyWindow = window
            })
        cycleItem.target = actions

        let action = try XCTUnwrap(cycleItem.action)
        XCTAssertTrue(NSApp.sendAction(action, to: cycleItem.target, from: cycleItem))
        XCTAssertEqual(activated.count, 1)
        XCTAssertTrue(activated[0] === second)

        XCTAssertTrue(NSApp.sendAction(action, to: cycleItem.target, from: cycleItem))
        XCTAssertEqual(activated.count, 2)
        XCTAssertTrue(activated[1] === first)
    }

    private func makeWindow(
        title: String,
        isVisible: Bool = true,
        isMiniaturized: Bool = false,
        canBecomeKey: Bool = true
    ) -> NSWindow {
        WindowFixture(
            title: title,
            isVisible: isVisible,
            isMiniaturized: isMiniaturized,
            canBecomeKey: canBecomeKey)
    }

    private final class WindowFixture: NSWindow {
        private let fixtureIsVisible: Bool
        private let fixtureIsMiniaturized: Bool
        private let fixtureCanBecomeKey: Bool

        override var isVisible: Bool { fixtureIsVisible }
        override var isMiniaturized: Bool { fixtureIsMiniaturized }
        override var canBecomeKey: Bool { fixtureCanBecomeKey }

        init(title: String, isVisible: Bool, isMiniaturized: Bool, canBecomeKey: Bool) {
            fixtureIsVisible = isVisible
            fixtureIsMiniaturized = isMiniaturized
            fixtureCanBecomeKey = canBecomeKey
            super.init(
                contentRect: NSRect(x: 120, y: 120, width: 320, height: 200),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            self.title = title
            isReleasedWhenClosed = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
