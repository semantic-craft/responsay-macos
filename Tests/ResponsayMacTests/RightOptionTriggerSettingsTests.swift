import XCTest
@testable import ResponsayMac

final class RightOptionTriggerSettingsTests: XCTestCase {
    func testDefaultIsExpressWhenUnset() {
        let defaults = freshDefaults("unset")
        XCTAssertEqual(RightOptionTriggerSettings.action(defaults: defaults), .expressInEnglish)
    }

    func testStoredActionWins() {
        let defaults = freshDefaults("stored")
        RightOptionTriggerSettings.setAction(.raw, defaults: defaults)
        XCTAssertEqual(RightOptionTriggerSettings.action(defaults: defaults), .raw)
    }

    func testDisabledReturnsNil() {
        let defaults = freshDefaults("disabled")
        RightOptionTriggerSettings.setAction(nil, defaults: defaults)
        XCTAssertNil(RightOptionTriggerSettings.action(defaults: defaults))
    }

    func testRightOptionAnchorIdentity() {
        XCTAssertEqual(HotkeyTrigger.anchor(.rightOptionOnly).id, "anchor:rightOption")
        XCTAssertEqual(HotkeyTrigger.anchor(.rightOptionHyper).id, "anchor:rightOption+shift+control+command")
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "RightOptionTriggerSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
