import XCTest
@testable import ResponsayMac

/// 界面语言下拉值 → AppleLanguages 覆盖的纯映射。explicit 语言写覆盖；
/// system / 未知值清覆盖（跟随系统）。
final class InterfaceLanguageTests: XCTestCase {
    func testExplicitLanguagesMapToOverrideArray() {
        XCTAssertEqual(InterfaceLanguage.appleLanguages(for: "en"), ["en"])
        XCTAssertEqual(InterfaceLanguage.appleLanguages(for: "zh-Hans"), ["zh-Hans"])
    }

    func testSystemClearsOverride() {
        XCTAssertNil(InterfaceLanguage.appleLanguages(for: "system"))
    }

    func testUnknownValueClearsOverride() {
        XCTAssertNil(InterfaceLanguage.appleLanguages(for: "fr"))
    }
}
