import XCTest
@testable import ResponsayMac

final class ShortcutActionTests: XCTestCase {
    func testVisibleActionsListIsTheBindableSettingsSet() {
        // askAnything / openApp / openSettings / confirmInsert are bindable (recordable)
        // shortcuts, so they appear in the settings list. translateSelection stays internal
        // (owned by hold-only selection interaction). legalPalette (选中文本法律技能) is retired
        // (划词技能互动): activated skills now route through the 划词菜单 / .selectionMenu.
        XCTAssertEqual(
            ShortcutAction.visibleInShortcutSettings,
            [.raw, .translate, .askAnything, .polish, .expressInEnglish,
             .rewriteSelection, .snapOCR, .snapTextOCR, .snapImageCopy, .selectionMenu,
             .readAloudSelection, .openApp, .openSettings, .confirmInsert]
        )
    }

    func testRetiredLegalPaletteActionDecodesOntoSelectionMenu() throws {
        // 划词技能互动 removed the legalPalette case entirely. A binding persisted under the old
        // "legalPalette" raw value must migrate onto its successor (.selectionMenu), not throw —
        // a throw fails the whole [ShortcutBinding] snapshot decode and resets every binding.
        let decoded = try JSONDecoder().decode(ShortcutAction.self, from: Data("\"legalPalette\"".utf8))
        XCTAssertEqual(decoded, .selectionMenu)
    }

    func testInternalSelectionTranslateIsNotShortcutBindable() {
        XCTAssertTrue(ShortcutAction.allCases.contains(.translateSelection))
        XCTAssertFalse(ShortcutAction.visibleInShortcutSettings.contains(.translateSelection))
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(ShortcutAction.raw.rawValue, "raw")
        XCTAssertEqual(ShortcutAction.translate.rawValue, "translate")
        XCTAssertEqual(ShortcutAction.polish.rawValue, "polish")
        XCTAssertEqual(ShortcutAction.expressInEnglish.rawValue, "expressInEnglish")
        XCTAssertEqual(ShortcutAction.rewriteSelection.rawValue, "rewriteSelection")
        XCTAssertEqual(ShortcutAction.translateSelection.rawValue, "translateSelection")
    }

    func testProductLabelsSeparatePolishFromEnglishExpression() {
        XCTAssertEqual(ShortcutAction.polish.title, "改写原话")
        XCTAssertEqual(ShortcutAction.translate.title, "听写翻译")
        XCTAssertEqual(ShortcutAction.expressInEnglish.title, "地道外文")
        XCTAssertTrue(ShortcutAction.polish.subtitle.contains("不翻译"))
        XCTAssertTrue(ShortcutAction.translate.subtitle.contains("目标语言"))
        XCTAssertTrue(ShortcutAction.translate.subtitle.contains("忠实准确"))
        XCTAssertTrue(ShortcutAction.expressInEnglish.subtitle.contains("Native Speaker"))
        XCTAssertTrue(ShortcutAction.expressInEnglish.subtitle.contains("中文讲解"))
        XCTAssertTrue(ShortcutAction.translateSelection.subtitle.contains("只做翻译"))
        XCTAssertTrue(ShortcutAction.translateSelection.subtitle.contains("不给地道外文讲解"))
    }

    func testRetiredCoachActionDecodesOntoExpressInEnglish() throws {
        // A binding persisted under the retired `coach` action must migrate, not throw —
        // otherwise the whole [ShortcutBinding] snapshot decode fails and resets bindings.
        let decoded = try JSONDecoder().decode(ShortcutAction.self, from: Data("\"coach\"".utf8))
        XCTAssertEqual(decoded, .expressInEnglish)
    }
}
