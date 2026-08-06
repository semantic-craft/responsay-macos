import XCTest
@testable import ResponsayMac

/// fn+V 划词菜单: a new global hotkey that pops the existing selection action menu
/// (来源核验 / 翻译 / 朗读 / 加入识别词典 …) on the current selection, read on demand.
@MainActor
final class SelectionMenuHotkeyTests: XCTestCase {
    // A fresh store seeds Fn+V → 划词菜单, so the default binding resolves out of the box.
    func testFreshStoreBindsFnVToSelectionMenu() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())

        XCTAssertEqual(store.action(for: .fnV), .selectionMenu)
    }

    // The router dispatches a 划词菜单 key-down to the showSelectionMenu handler.
    func testRouterRoutesSelectionMenuToHandler() {
        var didShowMenu = false
        let router = HotkeyActionRouter(handlers: HotkeyActionHandlers(
            isHoldToTalkEnabled: { true },
            beginCapture: { _, _ in },
            finishCurrentHotkeyAction: { _ in },
            rewriteSelection: {},
            translateSelection: {},
            snapOCR: {},
            snapTextOCR: {},
            snapImageCopy: {},
            showSelectionMenu: { didShowMenu = true },
            readAloudSelection: {},
            beginAskAnything: { _ in },
            finishAskAnything: { _ in },
            openApp: {},
            openSettings: {},
            confirmInsert: {}))

        router.handle(.down, action: .selectionMenu, trigger: .anchor(.fnV))

        XCTAssertTrue(didShowMenu)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ResponsayMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
