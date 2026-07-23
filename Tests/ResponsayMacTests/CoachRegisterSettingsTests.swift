import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 494 sample: `CoachRegisterSettings` is injectable (`defaults:`) so its read + derive
/// (`CoachRegister.resolve`) is unit-testable without polluting `UserDefaults.standard`. The
/// richer canonical exemplar of this pattern (with legacy migration) is `ExpressInsertSettingsTests`.
final class CoachRegisterSettingsTests: XCTestCase {

    func testFreshDefaultIsCasual() {
        XCTAssertEqual(CoachRegisterSettings.selectedRegister(defaults: fresh("fresh")), .casual)
    }

    func testStoredValueResolves() {
        let d = fresh("stored")
        d.set(CoachRegister.formal.rawValue, forKey: CoachRegisterSettings.key)
        XCTAssertEqual(CoachRegisterSettings.selectedRegister(defaults: d), .formal)
    }

    func testUnknownStoredValueFallsBackToDefault() {
        let d = fresh("garbage")
        d.set("not-a-register", forKey: CoachRegisterSettings.key)
        XCTAssertEqual(CoachRegisterSettings.selectedRegister(defaults: d), .casual)
    }

    private func fresh(_ suffix: String) -> UserDefaults {
        let name = "CoachRegisterSettingsTests.\(suffix)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
