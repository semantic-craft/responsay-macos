import XCTest
@testable import ResponsayMac

/// Ordinary Fn / right Option voice actions are tap-only. Persisted legacy gesture values are
/// ignored; selection interaction injects `.holdOnly` directly instead of going through settings.
final class TriggerGestureSettingsTests: XCTestCase {

    func testDefaultIsTapOnlyForEveryVoiceFunction() {
        XCTAssertEqual(TriggerStyleSettings.defaultGesture(for: .raw), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.defaultGesture(for: .polish), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.defaultGesture(for: .expressInEnglish), .tapOnly)
    }

    func testUnsetFunctionResolvesToTapOnly() {
        let defaults = freshDefaults("unset")
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .raw, defaults: defaults), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .expressInEnglish, defaults: defaults), .tapOnly)
    }

    func testLegacyTapResolvesToTapOnly() {
        let defaults = freshDefaults("legacy-tap")
        TriggerStyleSettings.setStyle(.tap, for: .raw, defaults: defaults)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .raw, defaults: defaults), .tapOnly)
    }

    func testLegacyHoldIsIgnoredForOrdinaryHotkeys() {
        let defaults = freshDefaults("legacy-hold")
        TriggerStyleSettings.setStyle(.hold, for: .expressInEnglish, defaults: defaults)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .expressInEnglish, defaults: defaults), .tapOnly)
    }

    func testStoredHoldOnlyGestureIsIgnoredForOrdinaryHotkeys() {
        let defaults = freshDefaults("direct")
        TriggerStyleSettings.setGesture(.holdOnly, for: .raw, defaults: defaults)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .raw, defaults: defaults), .tapOnly)
    }

    func testStoredBothGestureIsIgnoredForOrdinaryHotkeys() {
        let defaults = freshDefaults("roundtrip")
        TriggerStyleSettings.setGesture(.both, for: .raw, defaults: defaults)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .raw, defaults: defaults), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(for: .polish, defaults: defaults), .tapOnly)
    }

    // MARK: - Pure raw→gesture mapping

    func testGestureFromRawAlwaysCollapsesToTapOnly() {
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: "hold"), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: "tap"), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: "holdOnly"), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: "both"), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: nil), .tapOnly)
        XCTAssertEqual(TriggerStyleSettings.gesture(fromRaw: "garbage"), .tapOnly)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TriggerGestureSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
