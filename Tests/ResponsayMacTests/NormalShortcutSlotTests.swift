import KeyboardShortcuts
import XCTest
@testable import ResponsayMac

final class NormalShortcutSlotTests: XCTestCase {
    func testEveryVisibleActionHasThreeSlots() {
        for action in ShortcutAction.visibleInShortcutSettings {
            XCTAssertEqual(NormalShortcutSlot.slots(for: action).count, 3)
        }
    }

    func testSlotNamesAreUniqueAndDoNotUseDots() {
        let names = ShortcutAction.visibleInShortcutSettings
            .flatMap(NormalShortcutSlot.slots(for:))
            .map(\.name.rawValue)

        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertFalse(names.contains { $0.contains(".") })
    }

    func testSlotZeroReusesLegacyNames() {
        XCTAssertEqual(NormalShortcutSlot(action: .raw, index: 0).name.rawValue, "basicDictation")
        XCTAssertEqual(NormalShortcutSlot(action: .polish, index: 0).name.rawValue, "rewriteDictation")
        XCTAssertEqual(NormalShortcutSlot(action: .expressInEnglish, index: 0).name.rawValue, "englishExpressionMode")
        XCTAssertEqual(NormalShortcutSlot(action: .rewriteSelection, index: 0).name.rawValue, "rewriteSelection")
        XCTAssertEqual(NormalShortcutSlot(action: .translateSelection, index: 0).name.rawValue, "translateSelection")
    }
}
