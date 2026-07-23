import XCTest
@testable import ResponsayMac

final class StyleProfileSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.styleProfileSettings"

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

    func testEnabledByDefault() {
        XCTAssertTrue(StyleProfileSettings.isEnabled(defaults: defaults))
    }

    func testEffectiveNilWhenNothingLearned() {
        XCTAssertNil(StyleProfileSettings.effectiveDescriptor(defaults: defaults))
    }

    func testLearnedUsedWhenNoOverride() {
        StyleProfileSettings.setLearned("偏简洁、主动语态", at: Date(), defaults: defaults)
        XCTAssertEqual(StyleProfileSettings.effectiveDescriptor(defaults: defaults), "偏简洁、主动语态")
        XCTAssertNotNil(StyleProfileSettings.lastBuiltAt(defaults: defaults))
    }

    func testOverrideWinsOverLearned() {
        StyleProfileSettings.setLearned("偏简洁", at: Date(), defaults: defaults)
        defaults.set("我手写的风格", forKey: StyleProfileSettings.overrideKey)
        XCTAssertEqual(StyleProfileSettings.effectiveDescriptor(defaults: defaults), "我手写的风格")
    }

    func testDisabledReturnsNilEvenWithLearned() {
        StyleProfileSettings.setLearned("偏简洁", at: Date(), defaults: defaults)
        StyleProfileSettings.setEnabled(false, defaults: defaults)
        XCTAssertNil(StyleProfileSettings.effectiveDescriptor(defaults: defaults))
    }
}
