import XCTest
@testable import ResponsayMac

final class AutoLearnHotwordModeSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.autoLearnHotwordModeSettings"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultModeIsLocalRules() {
        XCTAssertEqual(AutoLearnHotwordModeSettings.mode(defaults: defaults), .localRules)
    }

    func testAutoLearningDefaultsOff() {
        XCTAssertFalse(AutoLearnHotwordSettings.resolve(defaults: defaults))
    }

    func testAutoLearningRequiresUserOptIn() {
        defaults.set(true, forKey: AutoLearnHotwordSettings.key)

        XCTAssertTrue(AutoLearnHotwordSettings.resolve(defaults: defaults))
    }

    func testExplicitCorrectionLearningDefaultsOnAndCanBeDisabled() {
        XCTAssertTrue(ExplicitCorrectionLearningSettings.resolve(defaults: defaults))

        defaults.set(false, forKey: ExplicitCorrectionLearningSettings.key)

        XCTAssertFalse(ExplicitCorrectionLearningSettings.resolve(defaults: defaults))
    }

    func testUnknownStoredModeFallsBackToLocalRules() {
        defaults.set("serverSideMagic", forKey: AutoLearnHotwordModeSettings.key)

        XCTAssertEqual(AutoLearnHotwordModeSettings.mode(defaults: defaults), .localRules)
    }

    func testSelectPersistsChosenMode() {
        AutoLearnHotwordModeSettings.select(.localModel, defaults: defaults)

        XCTAssertEqual(AutoLearnHotwordModeSettings.mode(defaults: defaults), .localModel)
    }
}
