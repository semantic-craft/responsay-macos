import XCTest
@testable import ResponsayMac

final class FnSwallowDeciderTests: XCTestCase {

    private let vKeyCode: UInt16 = 9       // V
    private let spaceKeyCode: UInt16 = 49  // Space
    private let leftArrowKeyCode: UInt16 = 123  // not a letter/digit/space

    // MARK: - Fn chord window

    func testLetterSwallowedWhileFnWindowOpen() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        XCTAssertTrue(d.keyDown(keyCode: vKeyCode, comboMatch: false))
    }

    func testLetterPassesWhenNoWindowOpen() {
        var d = FnSwallowDecider()
        XCTAssertFalse(d.keyDown(keyCode: vKeyCode, comboMatch: false))
    }

    func testSpaceSwallowedWhileFnWindowOpen() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        XCTAssertTrue(d.keyDown(keyCode: spaceKeyCode, comboMatch: false))
    }

    func testNonLetterPassesThroughEvenWithWindowOpen() {
        // Fn+arrow / Fn+⌫ must still reach the system — only letters/digits/space are chord keys.
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        XCTAssertFalse(d.keyDown(keyCode: leftArrowKeyCode, comboMatch: false))
    }

    func testOnlyFirstLetterPerWindowIsSwallowed() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        XCTAssertTrue(d.keyDown(keyCode: vKeyCode, comboMatch: false))
        // window closed after the first match — a second letter leaks
        XCTAssertFalse(d.keyDown(keyCode: 11, comboMatch: false))  // B
    }

    func testWindowCloseStopsSwallowing() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        d.setFnWindow(open: false)  // 400ms timer / Fn-up
        XCTAssertFalse(d.keyDown(keyCode: vKeyCode, comboMatch: false))
    }

    // MARK: - Right Option window is independent

    func testRightOptionWindowSwallowsLetter() {
        var d = FnSwallowDecider()
        d.setRightOptionWindow(open: true)
        XCTAssertTrue(d.keyDown(keyCode: vKeyCode, comboMatch: false))
    }

    func testFnUpDoesNotCloseRightOptionWindow() {
        var d = FnSwallowDecider()
        d.setRightOptionWindow(open: true)
        d.setFnWindow(open: false)
        XCTAssertTrue(d.keyDown(keyCode: vKeyCode, comboMatch: false))
    }

    // MARK: - Combo bindings (⌃⌥⌘+letter)

    func testComboMatchSwallowsWithoutWindow() {
        var d = FnSwallowDecider()
        XCTAssertTrue(d.keyDown(keyCode: 16, comboMatch: true))  // Y, ⌃⌥⌘Y
    }

    func testComboMissPassesThrough() {
        var d = FnSwallowDecider()
        XCTAssertFalse(d.keyDown(keyCode: 16, comboMatch: false))
    }

    // MARK: - keyUp pairing

    func testKeyUpSwallowedAfterSwallowedKeyDown() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        _ = d.keyDown(keyCode: vKeyCode, comboMatch: false)
        XCTAssertTrue(d.keyUp(keyCode: vKeyCode))
    }

    func testOrphanKeyUpPassesThrough() {
        var d = FnSwallowDecider()
        XCTAssertFalse(d.keyUp(keyCode: vKeyCode))
    }

    func testKeyUpSwallowedOnlyOnce() {
        var d = FnSwallowDecider()
        d.setFnWindow(open: true)
        _ = d.keyDown(keyCode: vKeyCode, comboMatch: false)
        XCTAssertTrue(d.keyUp(keyCode: vKeyCode))
        XCTAssertFalse(d.keyUp(keyCode: vKeyCode))  // already removed
    }

    func testComboKeyUpPaired() {
        var d = FnSwallowDecider()
        _ = d.keyDown(keyCode: 16, comboMatch: true)
        XCTAssertTrue(d.keyUp(keyCode: 16))
    }

    // MARK: - Default letter set sanity

    func testDefaultLetterKeyCodesCoverLettersDigitsSpace() {
        let set = FnSwallowDecider.defaultLetterKeyCodes
        XCTAssertTrue(set.contains(9))   // V
        XCTAssertTrue(set.contains(49))  // Space
        XCTAssertTrue(set.contains(29))  // 0
        XCTAssertFalse(set.contains(123)) // left arrow
        XCTAssertEqual(set.count, 37)    // 26 letters + 10 digits + space
    }
}
