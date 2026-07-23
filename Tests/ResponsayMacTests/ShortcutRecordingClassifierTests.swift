import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ResponsayMac

final class ShortcutRecordingClassifierTests: XCTestCase {
    private let keyN: UInt16 = 45
    private let keyEsc: UInt16 = 53

    func testFnPlusLetter() {
        XCTAssertEqual(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.function], rightOptionDown: false),
            .anchorKey(anchor: .fn, keyCode: keyN))
    }

    func testHyperPlusLetter() {
        let hyper: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        XCTAssertEqual(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: hyper, rightOptionDown: false),
            .combo(keyCode: keyN, carbonModifiers: ComboHotkeyMatcher.carbonModifiers(from: hyper)))
    }

    func testCmdShiftPlusLetter() {
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        XCTAssertEqual(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: cmdShift, rightOptionDown: false),
            .combo(keyCode: keyN, carbonModifiers: cmdKey | shiftKey))
    }

    func testRightOptionPlusLetter() {
        XCTAssertEqual(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.option], rightOptionDown: true),
            .anchorKey(anchor: .rightOption, keyCode: keyN))
    }

    func testLeftOptionRejected() {
        // Bare Option without the right-Option key held is not in the whitelist (no ⌘/⌃).
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.option], rightOptionDown: false))
    }

    func testPlainLetterRejected() {
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [], rightOptionDown: false))
    }

    func testShiftOnlyRejected() {
        // ⇧N (no ⌘/⌃) is just capital N — must not be recordable.
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.shift], rightOptionDown: false))
    }

    func testSingleModifierComboRejected() {
        // ⌘N alone (one modifier) is below the 2-modifier safety floor — must not be recordable.
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.command], rightOptionDown: false))
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.control], rightOptionDown: false))
    }

    func testFnPlusModifierRejected() {
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(keyCode: keyN, modifierFlags: [.function, .shift], rightOptionDown: false))
    }

    func testNonAlphanumericRejected() {
        // Escape with Hyper held is still rejected — only A–Z / 0–9 / Space are bindable.
        XCTAssertNil(
            ShortcutRecordingClassifier.classify(
                keyCode: keyEsc, modifierFlags: [.command, .control, .option, .shift], rightOptionDown: false))
    }
}
