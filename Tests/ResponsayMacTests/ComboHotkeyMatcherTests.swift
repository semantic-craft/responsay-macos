import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ResponsayMac

final class ComboHotkeyMatcherTests: XCTestCase {
    /// Carbon modifiers for a full Hyper press (⌃⌥⇧⌘) — the value persisted for a Hyper+letter combo.
    private let hyper = cmdKey | shiftKey | optionKey | controlKey  // 6912

    func testHyperLetterMatches() {
        // Recorded Hyper+N (keycode 45, mods 6912) vs a pressed Hyper+N.
        XCTAssertTrue(ComboHotkeyMatcher.matches(
            recordedKeyCode: 45, recordedModifiers: hyper,
            pressedKeyCode: 45, pressedModifiers: hyper))
    }

    func testPlainLetterNeverMatches() {
        // Pressing bare N must not match a recorded Hyper+N (else normal typing gets swallowed).
        XCTAssertFalse(ComboHotkeyMatcher.matches(
            recordedKeyCode: 45, recordedModifiers: hyper,
            pressedKeyCode: 45, pressedModifiers: 0))
    }

    func testWrongKeyDoesNotMatch() {
        XCTAssertFalse(ComboHotkeyMatcher.matches(
            recordedKeyCode: 45, recordedModifiers: hyper,
            pressedKeyCode: 46, pressedModifiers: hyper))
    }

    func testRecordingWithoutCommandOrControlRejected() {
        // A recording of only ⌥⇧+key (no ⌘/⌃) is rejected so it can't shadow Option-typing.
        let optionShift = optionKey | shiftKey
        XCTAssertFalse(ComboHotkeyMatcher.matches(
            recordedKeyCode: 45, recordedModifiers: optionShift,
            pressedKeyCode: 45, pressedModifiers: optionShift))
    }

    func testCapsLockBitIgnored() {
        // A stray alphaLock bit on the pressed event must not spoil the match.
        XCTAssertTrue(ComboHotkeyMatcher.matches(
            recordedKeyCode: 45, recordedModifiers: hyper,
            pressedKeyCode: 45, pressedModifiers: hyper | alphaLock))
    }

    func testCarbonModifiersFromFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        XCTAssertEqual(ComboHotkeyMatcher.carbonModifiers(from: flags), hyper)
    }
}
