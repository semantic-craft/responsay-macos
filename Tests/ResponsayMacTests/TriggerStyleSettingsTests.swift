import XCTest
@testable import ResponsayMac

final class TriggerStyleSettingsTests: XCTestCase {
    func testDefaultsAllTapIncludingExpress() {
        // 地道外文 (expressInEnglish) changed from hold → tap per product decision 2026-06-14.
        XCTAssertEqual(TriggerStyleSettings.defaultStyle(for: .expressInEnglish), .tap)
        XCTAssertEqual(TriggerStyleSettings.defaultStyle(for: .raw), .tap)
        XCTAssertEqual(TriggerStyleSettings.defaultStyle(for: .polish), .tap)
    }

    func testStyleFallsBackToDefaultWhenUnset() {
        let defaults = freshDefaults("unset")
        XCTAssertEqual(TriggerStyleSettings.style(for: .expressInEnglish, defaults: defaults), .tap)
        XCTAssertEqual(TriggerStyleSettings.style(for: .raw, defaults: defaults), .tap)
    }

    func testOverrideWinsAndPersists() {
        let defaults = freshDefaults("override")
        // Override both away from the tap default → hold, and read them back.
        TriggerStyleSettings.setStyle(.hold, for: .expressInEnglish, defaults: defaults)
        TriggerStyleSettings.setStyle(.hold, for: .raw, defaults: defaults)

        XCTAssertEqual(TriggerStyleSettings.style(for: .expressInEnglish, defaults: defaults), .hold)
        XCTAssertEqual(TriggerStyleSettings.style(for: .raw, defaults: defaults), .hold)
    }

    func testOverrideOfOneActionDoesNotAffectAnother() {
        let defaults = freshDefaults("isolation")
        TriggerStyleSettings.setStyle(.hold, for: .raw, defaults: defaults)
        // polish untouched → still its default (tap)
        XCTAssertEqual(TriggerStyleSettings.style(for: .polish, defaults: defaults), .tap)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TriggerStyleSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
