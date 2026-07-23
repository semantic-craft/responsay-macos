import XCTest
@testable import ResponsayCore

final class SnapTranslateTargetTests: XCTestCase {
    // Default pair: 第一=中文, 第二=英语 (preserves the original 外文→中文 / 中文→英文 behaviour).
    private let zh = TranslationTargetLanguage.chineseSimplified
    private let en = TranslationTargetLanguage.englishUS

    private func auto(_ text: String, primary: TranslationTargetLanguage, secondary: TranslationTargetLanguage) -> TranslationTargetLanguage {
        SnapTranslateTarget.auto.resolved(for: text, primary: primary, secondary: secondary)
    }

    func testAutoForeignTextGoesToPrimary() {
        XCTAssertEqual(auto("The quick brown fox jumps.", primary: zh, secondary: en), .chineseSimplified)
    }

    func testAutoPrimaryTextGoesToSecondary() {
        XCTAssertEqual(auto("这是一段中文文本，需要翻译。", primary: zh, secondary: en), .englishUS)
    }

    func testAutoDigitsAndSymbolsGoToPrimary() {
        XCTAssertEqual(auto("1234 — 5678 (90%)", primary: zh, secondary: en), .chineseSimplified)
    }

    func testAutoMixedMostlyEnglishGoesToPrimary() {
        XCTAssertEqual(auto("GDP 增长 nominal vs real growth analysis report", primary: zh, secondary: en), .chineseSimplified)
    }

    // Configurable pair: 第二=德语 → a foreign screenshot still goes to 母语(中文); Chinese → 德语.
    func testAutoHonorsConfiguredSecondary() {
        XCTAssertEqual(auto("Guten Tag, wie geht es dir?", primary: zh, secondary: .german), .chineseSimplified)
        XCTAssertEqual(auto("这是中文。", primary: zh, secondary: .german), .german)
    }

    // Non-Chinese 第一语言 (第一=英语, 第二=中文): English source IS primary → secondary(中文);
    // Chinese source is NOT primary → primary(英语).
    func testAutoWithNonChinesePrimary() {
        XCTAssertEqual(auto("Hello there friend.", primary: en, secondary: zh), .chineseSimplified)
        XCTAssertEqual(auto("这是中文。", primary: en, secondary: zh), .englishUS)
    }

    func testExplicitTargetsIgnoreTextAndPair() {
        XCTAssertEqual(SnapTranslateTarget.chinese.resolved(for: "anything", primary: en, secondary: en), .chineseSimplified)
        XCTAssertEqual(SnapTranslateTarget.english.resolved(for: "随便", primary: zh, secondary: zh), .englishUS)
        XCTAssertEqual(SnapTranslateTarget.german.resolved(for: "x", primary: zh, secondary: en), .german)
        XCTAssertEqual(SnapTranslateTarget.japanese.resolved(for: "x", primary: zh, secondary: en), .japanese)
    }
}
