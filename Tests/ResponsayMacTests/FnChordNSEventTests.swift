import AppKit
import XCTest
@testable import ResponsayMac

final class FnChordNSEventTests: XCTestCase {
    func testModifierFlagsMapToFnChord() {
        XCTAssertEqual(FnChord.fromModifierFlags([.function]), .fnOnly)
        XCTAssertEqual(FnChord.fromModifierFlags([.function, .shift]), .fnShift)
        XCTAssertEqual(FnChord.fromModifierFlags([.function, .option]), .fnOption)
        XCTAssertEqual(FnChord.fromModifierFlags([.function, .control]), .fnControl)
        XCTAssertEqual(FnChord.fromModifierFlags([.function, .command]), .fnCommand)
    }

    func testUnrelatedFlagsAreIgnored() {
        XCTAssertEqual(FnChord.fromModifierFlags([.function, .capsLock]), .fnOnly)
    }

    func testRightOptionAnchorDoesNotRepeatOptionModifier() {
        XCTAssertEqual(
            FnChord.fromModifierFlags([.option, .shift], anchor: .rightOption),
            .rightOptionShift)
        XCTAssertEqual(
            FnChord.fromModifierFlags([.option, .shift, .control, .command], anchor: .rightOption),
            .rightOptionHyper)
    }
}
