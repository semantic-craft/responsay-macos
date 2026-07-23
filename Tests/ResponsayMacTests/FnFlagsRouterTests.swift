import AppKit
import XCTest
@testable import ResponsayMac

final class FnFlagsRouterTests: XCTestCase {

    private let fnKeyCode: UInt16 = 63
    private let rightOptionKeyCode: UInt16 = 61

    // MARK: - Fn key (keyCode 63)

    func testFnKeyWithFunctionFlagRoutesToFnDown() {
        let route = FnFlagsRouter.route(keyCode: fnKeyCode, modifierFlags: [.function])
        XCTAssertEqual(route, .anchorDown(.fn, [.function]))
    }

    func testFnKeyWithoutFunctionFlagRoutesToFnUp() {
        let route = FnFlagsRouter.route(keyCode: fnKeyCode, modifierFlags: [])
        XCTAssertEqual(route, .anchorUp(.fn))
    }

    func testFnDownCarriesAccumulatedModifiers() {
        // Fn pressed while Shift is already held — the flags must be forwarded verbatim
        // so the chord window opens with the right modifiers.
        let route = FnFlagsRouter.route(keyCode: fnKeyCode, modifierFlags: [.function, .shift])
        XCTAssertEqual(route, .anchorDown(.fn, [.function, .shift]))
    }

    // MARK: - Right Option anchor (keyCode 61, Fn NOT held)

    func testRightOptionPressedWithoutFunctionRoutesToAnchorDown() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.option])
        XCTAssertEqual(route, .anchorDown(.rightOption, [.option]))
    }

    func testRightOptionReleasedWithoutFunctionRoutesToAnchorUp() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [])
        XCTAssertEqual(route, .anchorUp(.rightOption))
    }

    func testRightOptionReleasedWhileHyperStillHoldsOptionRoutesToAnchorUp() {
        let route = FnFlagsRouter.route(
            keyCode: rightOptionKeyCode,
            modifierFlags: [.option, .shift, .control, .command],
            rightOptionIsActive: true)
        XCTAssertEqual(route, .anchorUp(.rightOption))
    }

    // MARK: - The key guard: right-Option WITH Fn held is a Fn chord, not right Option anchor

    func testRightOptionWithFunctionHeldRoutesToModifiersChangedNotRightOptionAnchor() {
        // Fn + right-Option == the fnOption chord; the right Option branch must NOT fire.
        // It falls through to modifiersChanged so the chord accumulates the option modifier.
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.function, .option])
        XCTAssertEqual(route, .modifiersChanged([.function, .option]))
    }

    // MARK: - Other modifier while Fn held → modifiersChanged

    func testOtherModifierWhileFunctionHeldRoutesToModifiersChanged() {
        // A Shift change (some non-Fn, non-right-Option keyCode) while Fn is held folds in.
        let route = FnFlagsRouter.route(keyCode: 56, modifierFlags: [.function, .shift])
        XCTAssertEqual(route, .modifiersChanged([.function, .shift]))
    }

    // MARK: - Other key, no Fn → ignore

    func testOtherKeyWithoutFunctionRoutesToIgnore() {
        let route = FnFlagsRouter.route(keyCode: 56, modifierFlags: [.shift])
        XCTAssertEqual(route, .ignore)
    }

    func testOtherModifierWhileRightOptionHeldRoutesToModifiersChanged() {
        let route = FnFlagsRouter.route(
            keyCode: 56,
            modifierFlags: [.option, .shift],
            rightOptionIsActive: true)
        XCTAssertEqual(route, .modifiersChanged([.option, .shift]))
    }

    func testNoModifiersNoFunctionRoutesToIgnore() {
        let route = FnFlagsRouter.route(keyCode: 56, modifierFlags: [])
        XCTAssertEqual(route, .ignore)
    }

    // MARK: - Hyper key (⌃⌥⌘⇧) / Option-combos must NOT fire the standalone Option trigger
    //
    // A "Hyper key" remaps one physical key to all four modifiers at once. Because Option is
    // among them, the standalone-Option trigger misfired and opened 任意提问 on every Hyper
    // press. The bare-Option trigger is only valid when Option is the SOLE modifier — any
    // Command/Control/Shift companion means it's a chord (Hyper or otherwise), not a tap.
    // The down edge is suppressed here; the orphan-up guard in HotkeyDispatchTable then makes
    // the matching release a no-op, so no stray action fires.

    private let leftOptionKeyCode: UInt16 = 58

    func testHyperKeyOnRightOptionKeyCodeDoesNotRouteToStandalone() {
        let route = FnFlagsRouter.route(
            keyCode: rightOptionKeyCode, modifierFlags: [.control, .option, .command, .shift])
        XCTAssertEqual(route, .ignore)
    }

    func testHyperKeyOnLeftOptionKeyCodeDoesNotRouteToStandalone() {
        let route = FnFlagsRouter.route(
            keyCode: leftOptionKeyCode, modifierFlags: [.control, .option, .command, .shift])
        XCTAssertEqual(route, .ignore)
    }

    func testOptionWithCommandDoesNotRouteToStandalone() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.option, .command])
        XCTAssertEqual(route, .ignore)
    }

    func testOptionWithControlDoesNotRouteToStandalone() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.option, .control])
        XCTAssertEqual(route, .ignore)
    }

    func testOptionWithShiftDoesNotRouteToStandalone() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.option, .shift])
        XCTAssertEqual(route, .ignore)
    }

    // Regression guards: the genuine solo right-Option anchor must still fire after the fix.

    func testSoloRightOptionStillRoutesToAnchorDown() {
        let route = FnFlagsRouter.route(keyCode: rightOptionKeyCode, modifierFlags: [.option])
        XCTAssertEqual(route, .anchorDown(.rightOption, [.option]))
    }

    func testSoloLeftOptionIsNotHandledByRightOptionAnchorRouter() {
        let route = FnFlagsRouter.route(keyCode: leftOptionKeyCode, modifierFlags: [.option])
        XCTAssertEqual(route, .ignore)
    }
}
