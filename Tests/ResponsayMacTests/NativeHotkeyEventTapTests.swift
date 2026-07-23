import AppKit
import OSLog
import XCTest
@testable import ResponsayMac

@MainActor
final class NativeHotkeyEventTapTests: XCTestCase {
    private let vKeyCode: UInt16 = 9
    private let yKeyCode: UInt16 = 16

    private func makeTap() -> NativeHotkeyEventTap {
        NativeHotkeyEventTap(log: Logger(subsystem: "test", category: "native-hotkey"))
    }

    private func fnDown(_ tap: NativeHotkeyEventTap, at t: TimeInterval) {
        _ = tap.decideSwallowForTesting(
            .flagsChanged(keyCode: FnFlagsRouter.fnKeyCode, modifierFlags: [.function]), at: t)
    }

    func testMapsSupportedCGEventTypes() {
        XCTAssertEqual(
            NativeHotkeyEvent.make(type: .flagsChanged, keyCode: FnFlagsRouter.fnKeyCode, modifierFlags: [.function]),
            .flagsChanged(keyCode: FnFlagsRouter.fnKeyCode, modifierFlags: [.function]))
        XCTAssertEqual(NativeHotkeyEvent.make(type: .keyDown, keyCode: 49), .keyDown(keyCode: 49, modifierFlags: []))
        XCTAssertEqual(NativeHotkeyEvent.make(type: .keyUp, keyCode: 49), .keyUp(keyCode: 49))
        XCTAssertNil(NativeHotkeyEvent.make(type: .leftMouseDown, keyCode: 0))
    }

    // MARK: - Fn chord swallow

    func testFnChordSwallowsLetterAndPairsKeyUp() {
        let tap = makeTap()
        fnDown(tap, at: 0)
        XCTAssertTrue(tap.decideSwallowForTesting(.keyDown(keyCode: vKeyCode, modifierFlags: [.function]), at: 0.1))
        XCTAssertTrue(tap.decideSwallowForTesting(.keyUp(keyCode: vKeyCode), at: 0.2))
    }

    func testFnChordDoesNotSwallowAfterWindowExpires() {
        let tap = makeTap()
        fnDown(tap, at: 0)
        XCTAssertFalse(tap.decideSwallowForTesting(.keyDown(keyCode: vKeyCode, modifierFlags: [.function]), at: 0.5))
    }

    func testLetterPassesWithoutAnchor() {
        let tap = makeTap()
        XCTAssertFalse(tap.decideSwallowForTesting(.keyDown(keyCode: vKeyCode, modifierFlags: []), at: 0))
    }

    func testFlagsChangedNeverSwallowed() {
        let tap = makeTap()
        XCTAssertFalse(tap.decideSwallowForTesting(
            .flagsChanged(keyCode: FnFlagsRouter.fnKeyCode, modifierFlags: [.function]), at: 0))
    }

    // MARK: - Recording mode

    func testRecordingSwallowsEveryKeyButNotFlags() {
        let tap = makeTap()
        tap.setRecording(true)
        XCTAssertTrue(tap.decideSwallowForTesting(.keyDown(keyCode: vKeyCode, modifierFlags: []), at: 0))
        XCTAssertTrue(tap.decideSwallowForTesting(.keyUp(keyCode: vKeyCode), at: 0))
        XCTAssertFalse(tap.decideSwallowForTesting(
            .flagsChanged(keyCode: FnFlagsRouter.fnKeyCode, modifierFlags: [.function]), at: 0))
    }

    func testRecordingClearedRestoresNormalSwallow() {
        let tap = makeTap()
        tap.setRecording(true)
        tap.setRecording(false)
        XCTAssertFalse(tap.decideSwallowForTesting(.keyDown(keyCode: vKeyCode, modifierFlags: []), at: 0))
    }

    // MARK: - Combo bindings

    func testComboMatchSwallowedAndPaired() {
        let tap = makeTap()
        let mods = ComboHotkeyMatcher.carbonModifiers(from: [.command, .option, .control])
        tap.setComboMatchTable([yKeyCode: [mods]])
        XCTAssertTrue(tap.decideSwallowForTesting(
            .keyDown(keyCode: yKeyCode, modifierFlags: [.command, .option, .control]), at: 0))
        XCTAssertTrue(tap.decideSwallowForTesting(.keyUp(keyCode: yKeyCode), at: 0))
    }

    func testComboWrongModifiersPassesThrough() {
        let tap = makeTap()
        let mods = ComboHotkeyMatcher.carbonModifiers(from: [.command, .option, .control])
        tap.setComboMatchTable([yKeyCode: [mods]])
        XCTAssertFalse(tap.decideSwallowForTesting(.keyDown(keyCode: yKeyCode, modifierFlags: [.command]), at: 0))
    }
}
