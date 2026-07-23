import XCTest
@testable import ResponsayMac

private final class ChordRecorder: @unchecked Sendable {
    var downs: [FnChord] = []
    var ups: [FnChord] = []
}

@MainActor
final class FnChordStateMachineTests: XCTestCase {

    private var sm: FnChordStateMachine!
    private let recorder = ChordRecorder()

    override func setUp() {
        recorder.downs = []
        recorder.ups = []
        let r = recorder
        sm = FnChordStateMachine(
            letterKeyTimeout: 0.4,
            onDown: { chord in r.downs.append(chord) },
            onUp: { chord in r.ups.append(chord) }
        )
    }

    private var emittedDown: [FnChord] { recorder.downs }
    private var emittedUp: [FnChord] { recorder.ups }

    // MARK: - Stage One (modifier-only, existing behavior)

    func testFnDownUpEmitsModifierOnlyChord() {
        sm.fnDown(modifierFlags: [])
        XCTAssertTrue(emittedDown.isEmpty, "should wait for potential letter key")

        sm.fnUp()
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first, .fnOnly)
        XCTAssertEqual(emittedUp.count, 1)
        XCTAssertEqual(emittedUp.first, .fnOnly)
    }

    func testFnShiftDownUpEmitsShiftChord() {
        sm.fnDown(modifierFlags: [.shift])
        sm.fnUp()
        XCTAssertEqual(emittedDown.first, .fnShift)
        XCTAssertEqual(emittedUp.first, .fnShift)
    }

    // MARK: - Stage Two (Fn + letter key)

    func testFnDownThenLetterEmitsKeyChord() {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 5) // G
        XCTAssertEqual(emittedDown.count, 1)
        let chord = emittedDown.first!
        XCTAssertEqual(chord.key?.display, "G")
        XCTAssertEqual(chord.modifiers, [])
    }

    func testFnDownThenLetterThenFnUpEmitsUpWithKey() {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 5)
        sm.fnUp()
        XCTAssertEqual(emittedUp.count, 1)
        XCTAssertEqual(emittedUp.first?.key?.display, "G")
    }

    func testFnShiftThenLetterEmitsShiftKeyChord() {
        sm.fnDown(modifierFlags: [.shift])
        sm.letterKeyDown(keyCode: 5) // G
        let chord = emittedDown.first!
        XCTAssertEqual(chord.modifiers, [.shift])
        XCTAssertEqual(chord.key?.display, "G")
        XCTAssertEqual(chord.id, "fn+shift+g")
    }

    func testLetterKeySwallowed() {
        sm.fnDown(modifierFlags: [])
        let shouldSwallow = sm.letterKeyDown(keyCode: 5)
        XCTAssertTrue(shouldSwallow, "letter key should be swallowed to prevent typing")
    }

    func testUnknownKeyCodeNotSwallowed() {
        sm.fnDown(modifierFlags: [])
        let shouldSwallow = sm.letterKeyDown(keyCode: 999)
        XCTAssertFalse(shouldSwallow, "unknown keyCode should not be swallowed")
        XCTAssertTrue(emittedDown.isEmpty, "should not emit chord for unknown key")
    }

    // MARK: - Timeout fallback

    func testTimeoutFallsBackToModifierOnly() async throws {
        sm.fnDown(modifierFlags: [])
        XCTAssertTrue(emittedDown.isEmpty)

        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first, .fnOnly)
    }

    func testLetterBeforeTimeoutCancelsTimeout() async throws {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 17) // T
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first?.key?.display, "T")

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(emittedDown.count, 1, "timeout should not emit a second chord")
    }

    // MARK: - Edge cases

    func testFnUpBeforeTimeoutWithNoLetterEmitsModifierOnly() {
        sm.fnDown(modifierFlags: [.option])
        sm.fnUp()
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first, .fnOption)
    }

    func testLetterWithoutFnDownIsIgnored() {
        let shouldSwallow = sm.letterKeyDown(keyCode: 5)
        XCTAssertFalse(shouldSwallow)
        XCTAssertTrue(emittedDown.isEmpty)
    }

    func testDoubleFnDownIsIdempotent() {
        sm.fnDown(modifierFlags: [])
        sm.fnDown(modifierFlags: [])
        sm.fnUp()
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedUp.count, 1)
    }

    func testOnlyFirstLetterCountsDuringOnePress() {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 5) // G
        sm.letterKeyDown(keyCode: 17) // T — should be ignored
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first?.key?.display, "G")
    }

    func testSecondFnPressAfterFullCycleWorks() {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 5)
        sm.fnUp()

        recorder.downs.removeAll()
        recorder.ups.removeAll()

        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 17) // T
        sm.fnUp()

        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first?.key?.display, "T")
        XCTAssertEqual(emittedUp.count, 1)
    }

    // MARK: - Modifier added/removed after Fn down (the Fn-then-Shift ordering fix)

    /// The real-world bug: pressing Fn+⇧, Fn lands a few ms before ⇧, so the chord
    /// froze as `fn` (→ 语音输入) instead of `fn+shift` (→ 翻译). A modifier added
    /// during the wait window must fold into the pending chord.
    func testModifierAddedAfterFnDownUpdatesChordOnFnUp() {
        sm.fnDown(modifierFlags: [])             // Fn first, no shift yet
        sm.modifiersChanged(modifierFlags: [.shift]) // ⇧ added while Fn held
        sm.fnUp()
        XCTAssertEqual(emittedDown.first, .fnShift)
        XCTAssertEqual(emittedUp.first, .fnShift)
    }

    func testModifierAddedAfterFnDownUpdatesChordOnTimeout() async throws {
        sm.fnDown(modifierFlags: [])
        sm.modifiersChanged(modifierFlags: [.shift])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first, .fnShift)
    }

    func testModifierAddedThenLetterKeptInChord() {
        sm.fnDown(modifierFlags: [])
        sm.modifiersChanged(modifierFlags: [.shift])
        sm.letterKeyDown(keyCode: 14) // E
        let chord = emittedDown.first!
        XCTAssertEqual(chord.modifiers, [.shift])
        XCTAssertEqual(chord.key?.display, "E")
    }

    /// Quick Fn+⇧ tap: ⇧ is released a hair before Fn. The chord must NOT collapse back
    /// to fn — a modifier held with Fn at any point in the window is accumulated.
    func testModifierReleasedBeforeFnUpStaysAccumulated() {
        sm.fnDown(modifierFlags: [.shift])
        sm.modifiersChanged(modifierFlags: []) // ⇧ released while Fn still held
        sm.fnUp()
        XCTAssertEqual(emittedDown.first, .fnShift)
        XCTAssertEqual(emittedUp.first, .fnShift)
    }

    /// The full real-world quick tap, Fn first: Fn down → ⇧ down → ⇧ up → Fn up, all
    /// inside the window. Must resolve to fn+shift (the bug produced fn → 语音输入).
    func testFnFirstQuickTapWithReleaseResolvesToShift() {
        sm.fnDown(modifierFlags: [])
        sm.modifiersChanged(modifierFlags: [.shift]) // ⇧ down
        sm.modifiersChanged(modifierFlags: [])       // ⇧ up
        sm.fnUp()
        XCTAssertEqual(emittedDown.first, .fnShift)
        XCTAssertEqual(emittedUp.first, .fnShift)
    }

    func testModifiersChangedIgnoredWhenIdle() {
        sm.modifiersChanged(modifierFlags: [.shift])
        XCTAssertTrue(emittedDown.isEmpty)
    }

    func testModifiersChangedIgnoredAfterLetterMatched() {
        sm.fnDown(modifierFlags: [])
        sm.letterKeyDown(keyCode: 5) // G — chord fires immediately
        sm.modifiersChanged(modifierFlags: [.shift]) // too late
        sm.fnUp()
        XCTAssertEqual(emittedDown.count, 1)
        XCTAssertEqual(emittedDown.first?.modifiers, [])
    }

    func testRightOptionAnchorExcludesOptionFromChord() {
        let r = recorder
        sm = FnChordStateMachine(
            anchor: .rightOption,
            letterKeyTimeout: 0.4,
            onDown: { chord in r.downs.append(chord) },
            onUp: { chord in r.ups.append(chord) }
        )

        sm.anchorDown(modifierFlags: [.option, .shift])
        sm.anchorUp()

        XCTAssertEqual(emittedDown.first, .rightOptionShift)
        XCTAssertEqual(emittedUp.first, .rightOptionShift)
    }
}
