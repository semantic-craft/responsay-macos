import XCTest
@testable import ResponsayMac

final class CaptureTriggerModeSettingsTests: XCTestCase {
    // The trigger model is now fixed to tap-to-start / tap-to-stop. Hold-to-talk and
    // double-tap were removed, and any stale preference for them must be ignored.

    func testModeIsAlwaysToggle() {
        XCTAssertEqual(CaptureTriggerModeSettings.mode(defaults: freshDefaults("default")), .toggle)
    }

    func testStaleHoldPreferenceIsIgnored() {
        let defaults = freshDefaults("stale-hold")
        defaults.set("hold", forKey: "triggerMode")
        defaults.set(true, forKey: "triggerMode")

        XCTAssertEqual(CaptureTriggerModeSettings.mode(defaults: defaults), .toggle)
        XCTAssertFalse(CaptureTriggerModeSettings.isHoldToTalk(defaults: defaults))
    }

    func testStaleDoubleTapPreferenceIsIgnored() {
        let defaults = freshDefaults("stale-double")
        defaults.set("double", forKey: "triggerMode")
        defaults.set(true, forKey: "doubleTapEnabled")

        XCTAssertEqual(CaptureTriggerModeSettings.mode(defaults: defaults), .toggle)
        XCTAssertFalse(CaptureTriggerModeSettings.isDoubleTap(defaults: defaults))
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "CaptureTriggerModeSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
