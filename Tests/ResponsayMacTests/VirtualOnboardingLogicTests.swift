import AppKit
import XCTest
@testable import ResponsayMac

/// Pure-logic tests for the interactive guided first-run (spec §7).
/// T1: no UI host, no network. The honesty-core decision is the load-bearing part.
final class VirtualOnboardingLogicTests: XCTestCase {

    // MARK: - Hotkey calibration state machine (spec §4.1)

    func testCalibrationStartsIdleAndCannotConfirm() {
        let c = HotkeyCalibration()
        XCTAssertEqual(c.state, .idle)
        XCTAssertFalse(c.canConfirm)
        XCTAssertFalse(c.isConfirmed)
    }

    func testCalibrationConfirmIgnoredBeforeRealPress() {
        var c = HotkeyCalibration()
        c.confirm()
        XCTAssertEqual(c.state, .idle, "是的，继续 must do nothing before a real press is observed")
        XCTAssertFalse(c.isConfirmed)
    }

    func testCalibrationKeyPressEnablesConfirm() {
        var c = HotkeyCalibration()
        c.keyPressed()
        XCTAssertEqual(c.state, .detected)
        XCTAssertTrue(c.canConfirm)
    }

    func testCalibrationConfirmAfterPress() {
        var c = HotkeyCalibration()
        c.keyPressed()
        c.confirm()
        XCTAssertEqual(c.state, .confirmed)
        XCTAssertTrue(c.isConfirmed)
    }

    func testCalibrationResetReturnsToIdle() {
        var c = HotkeyCalibration()
        c.keyPressed()
        c.reset()
        XCTAssertEqual(c.state, .idle)
        XCTAssertFalse(c.canConfirm)
    }

    // MARK: - Sandbox sequence progression (spec §4.2)

    func testSequenceStartsAtFirstFlow() {
        let s = SandboxSequence()
        XCTAssertEqual(s.current, .dictate)
        XCTAssertFalse(s.isComplete)
        XCTAssertEqual(s.progress, "1/4")
    }

    func testSequenceAdvanceWalksFlowsInOrder() {
        var s = SandboxSequence()
        s.advance(); XCTAssertEqual(s.current, .translate); XCTAssertEqual(s.progress, "2/4")
        s.advance(); XCTAssertEqual(s.current, .ask)
        s.advance(); XCTAssertEqual(s.current, .verify); XCTAssertEqual(s.progress, "4/4")
        s.advance(); XCTAssertNil(s.current); XCTAssertTrue(s.isComplete)
    }

    func testSequenceAdvancePastEndStaysComplete() {
        var s = SandboxSequence()
        for _ in 0..<10 { s.advance() }
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.current)
    }

    func testSequenceSkipAllCompletesImmediately() {
        var s = SandboxSequence()
        s.skipAll()
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.current)
    }

    func testSequenceBackStepsThroughFlowsAndClampsAtFirst() {
        var s = SandboxSequence()
        s.advance(); s.advance()                          // → .ask
        XCTAssertEqual(s.current, .ask)
        s.back(); XCTAssertEqual(s.current, .translate)
        s.back(); XCTAssertEqual(s.current, .dictate)
        s.back(); XCTAssertEqual(s.current, .dictate, "back clamps at the first flow")
        XCTAssertEqual(s.progress, "1/4")
    }

    // MARK: - Calibration matcher (HotkeyCalibrationMonitor.matches, spec §4.1)

    func testFnSchemeMatchesFnFlagChangeOnly() {
        XCTAssertTrue(HotkeyCalibrationMonitor.matches(type: .flagsChanged, modifiers: [.function], scheme: .fn))
        XCTAssertFalse(HotkeyCalibrationMonitor.matches(type: .flagsChanged, modifiers: [.command], scheme: .fn))
        XCTAssertFalse(HotkeyCalibrationMonitor.matches(type: .keyDown, modifiers: [.function], scheme: .fn),
                       "Fn registers as a flag change, not a keyDown")
    }

    func testComboSchemeMatchesControlOptionCommandKeyDown() {
        XCTAssertTrue(HotkeyCalibrationMonitor.matches(type: .keyDown, modifiers: [.control, .option, .command], scheme: .other))
        XCTAssertTrue(HotkeyCalibrationMonitor.matches(type: .keyDown, modifiers: [.control, .option, .command, .shift], scheme: .other),
                      "extra modifiers still match (superset)")
        XCTAssertFalse(HotkeyCalibrationMonitor.matches(type: .keyDown, modifiers: [.control, .option], scheme: .other),
                       "missing ⌘ → no match")
        XCTAssertFalse(HotkeyCalibrationMonitor.matches(type: .flagsChanged, modifiers: [.control, .option, .command], scheme: .other),
                       "combo needs the actual keyDown, not just held modifiers")
    }

    // MARK: - Sandbox hands-on gestures (SandboxGesture.matches)

    func testFnShiftGestureMatchesFunctionPlusShiftFlagChange() {
        XCTAssertTrue(SandboxGesture.matches(type: .flagsChanged, modifiers: [.function, .shift], keyCode: 0, gesture: .fnShift))
        XCTAssertFalse(SandboxGesture.matches(type: .flagsChanged, modifiers: [.function], keyCode: 0, gesture: .fnShift),
                       "Fn alone is not Fn+Shift")
        XCTAssertFalse(SandboxGesture.matches(type: .keyDown, modifiers: [.function, .shift], keyCode: 0, gesture: .fnShift),
                       "the modifier chord registers as a flag change, not a keyDown")
    }

    func testFnSpaceGestureMatchesFunctionSpaceKeyDown() {
        XCTAssertTrue(SandboxGesture.matches(type: .keyDown, modifiers: [.function], keyCode: 49, gesture: .fnSpace))
        XCTAssertFalse(SandboxGesture.matches(type: .keyDown, modifiers: [], keyCode: 49, gesture: .fnSpace),
                       "Space without Fn is not Fn Space")
        XCTAssertFalse(SandboxGesture.matches(type: .keyDown, modifiers: [.function], keyCode: 0, gesture: .fnSpace),
                       "Fn + a non-space key is not Fn Space")
    }

    func testFnVGestureMatchesFunctionVKeyDown() {
        XCTAssertTrue(SandboxGesture.matches(type: .keyDown, modifiers: [.function], keyCode: 9, gesture: .fnV),
                      "keyCode 9 = V; fn+V is the 划词菜单 / 来源核验 trigger")
        XCTAssertFalse(SandboxGesture.matches(type: .keyDown, modifiers: [], keyCode: 9, gesture: .fnV),
                       "V without Fn is not fn+V")
        XCTAssertFalse(SandboxGesture.matches(type: .keyDown, modifiers: [.function], keyCode: 49, gesture: .fnV),
                       "Fn + a non-V key is not fn+V")
    }
}
