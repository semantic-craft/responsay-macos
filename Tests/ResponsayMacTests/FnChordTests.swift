import XCTest
@testable import ResponsayMac

final class FnChordTests: XCTestCase {
    func testDisplayStrings() {
        XCTAssertEqual(FnChord.fnOnly.displayString, "Fn")
        XCTAssertEqual(FnChord.fnShift.displayString, "Fn ⇧")
        XCTAssertEqual(FnChord.fnOption.displayString, "Fn ⌥")
        XCTAssertEqual(FnChord.fnControl.displayString, "Fn ⌃")
        XCTAssertEqual(FnChord.fnCommand.displayString, "Fn ⌘")
    }

    func testCodableRoundTrip() throws {
        let chord = FnChord(modifiers: [.shift, .command], key: FnKey(keyCode: 49, display: "Space"))
        let data = try JSONEncoder().encode(chord)
        let decoded = try JSONDecoder().decode(FnChord.self, from: data)

        XCTAssertEqual(decoded, chord)
        XCTAssertEqual(decoded.displayString, "Fn ⇧ ⌘ Space")
    }

    func testLegacyCodableWithoutAnchorDecodesAsFn() throws {
        let data = Data(#"{"modifiers":["shift"]}"#.utf8)
        let decoded = try JSONDecoder().decode(FnChord.self, from: data)
        XCTAssertEqual(decoded, .fnShift)
    }

    func testStageOneAllowedHasNoDuplicates() {
        let ids = FnChord.stageOneAllowed.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids, ["fn", "fn+shift", "fn+option", "fn+control", "fn+command"])
    }

    func testRightOptionStageOneAllowedHasNoDuplicates() {
        let ids = FnChord.stageOneAllowed(for: .rightOption).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids, [
            "rightOption",
            "rightOption+shift",
            "rightOption+control",
            "rightOption+command"
        ])
    }

    func testSettingsQuickAddIncludesFnSpace() {
        let ids = FnChord.settingsQuickAddAllowed.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids, ["fn", "fn+shift", "fn+option", "fn+control", "fn+command", "fn+space", "fn+v", "fn+e"])
        XCTAssertEqual(FnChord.fnSpace.displayString, "Fn Space")
        XCTAssertEqual(FnChord.fnV.displayString, "Fn V")
        XCTAssertEqual(FnChord.fnE.displayString, "Fn E")
    }

    // MARK: - Issue 271: FnKey model enrichment

    func testFnKeyFromKeyCodeLetters() {
        XCTAssertEqual(FnKey.from(keyCode: 0)?.display, "A")
        XCTAssertEqual(FnKey.from(keyCode: 11)?.display, "B")
        XCTAssertEqual(FnKey.from(keyCode: 8)?.display, "C")
        XCTAssertEqual(FnKey.from(keyCode: 5)?.display, "G")
        XCTAssertEqual(FnKey.from(keyCode: 17)?.display, "T")
        XCTAssertEqual(FnKey.from(keyCode: 45)?.display, "N")
        XCTAssertEqual(FnKey.from(keyCode: 46)?.display, "M")
    }

    func testFnKeyFromKeyCodeDigits() {
        XCTAssertEqual(FnKey.from(keyCode: 29)?.display, "0")
        XCTAssertEqual(FnKey.from(keyCode: 18)?.display, "1")
        XCTAssertEqual(FnKey.from(keyCode: 19)?.display, "2")
        XCTAssertEqual(FnKey.from(keyCode: 25)?.display, "9")
    }

    func testFnKeyFromKeyCodeSpace() {
        XCTAssertEqual(FnKey.from(keyCode: 49)?.display, "Space")
        XCTAssertEqual(FnKey.from(keyCode: 49), .space)
    }

    func testFnKeyFromUnknownKeyCodeReturnsNil() {
        XCTAssertNil(FnKey.from(keyCode: 999))
    }

    func testFnKeyCoversAllLetters() {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let found = (0..<128).compactMap { FnKey.from(keyCode: UInt16($0)) }
            .filter { $0.display.count == 1 && $0.display.first!.isLetter }
        XCTAssertEqual(Set(found.map(\.display)), Set(letters.map(String.init)))
    }

    func testFnChordWithKeyDisplayString() {
        let g = FnKey.from(keyCode: 5)!
        XCTAssertEqual(FnChord(modifiers: [], key: g).displayString, "Fn G")
        XCTAssertEqual(FnChord(modifiers: [.shift], key: g).displayString, "Fn ⇧ G")
        XCTAssertEqual(FnChord(modifiers: [.shift, .option], key: g).displayString, "Fn ⇧ ⌥ G")
        XCTAssertEqual(FnChord(anchor: .rightOption, modifiers: [], key: g).displayString, "右 Option G")
        XCTAssertEqual(FnChord(anchor: .rightOption, modifiers: [.shift], key: g).displayString, "右 Option ⇧ G")
    }

    func testFnChordWithKeyId() {
        let g = FnKey.from(keyCode: 5)!
        XCTAssertEqual(FnChord(modifiers: [], key: g).id, "fn+g")
        XCTAssertEqual(FnChord(modifiers: [.shift], key: g).id, "fn+shift+g")

        let t = FnKey.from(keyCode: 17)!
        XCTAssertEqual(FnChord(modifiers: [], key: t).id, "fn+t")
        XCTAssertEqual(FnChord(anchor: .rightOption, modifiers: [], key: t).id, "rightOption+t")
    }

    func testFnChordWithKeyCodableRoundTrip() throws {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [.shift], key: g)
        let data = try JSONEncoder().encode(chord)
        let decoded = try JSONDecoder().decode(FnChord.self, from: data)
        XCTAssertEqual(decoded, chord)
        XCTAssertEqual(decoded.key?.display, "G")
        XCTAssertEqual(decoded.key?.keyCode, 5)
    }

    func testFnChordWithKeyNotEqualToModifierOnly() {
        let g = FnKey.from(keyCode: 5)!
        let withKey = FnChord(modifiers: [.shift], key: g)
        let withoutKey = FnChord.fnShift
        XCTAssertNotEqual(withKey, withoutKey)
    }

    func testStageOneAllowedUnchanged() {
        XCTAssertEqual(FnChord.stageOneAllowed.count, 5)
        XCTAssertTrue(FnChord.stageOneAllowed.allSatisfy { $0.key == nil })
    }

    func testIsLetterKeyChord() {
        let g = FnKey.from(keyCode: 5)!
        XCTAssertTrue(FnChord(modifiers: [], key: g).isLetterKeyChord)
        XCTAssertFalse(FnChord.fnOnly.isLetterKeyChord)
        XCTAssertFalse(FnChord.fnShift.isLetterKeyChord)
    }
}
