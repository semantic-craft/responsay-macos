import XCTest
@testable import ResponsayMac

final class HotkeyDispatchTableTests: XCTestCase {

    private var table = HotkeyDispatchTable()

    override func setUp() {
        super.setUp()
        table = HotkeyDispatchTable()
    }

    // MARK: - Fn chord down

    func testDownWithActionRecordsAndReturnsDownCommand() {
        let command = table.down(.fnOnly, resolvedAction: .raw)
        XCTAssertEqual(command, HotkeyRouteCommand(phase: .down, action: .raw, trigger: .anchor(.fnOnly)))
    }

    func testDownWithNilActionReturnsNil() {
        let command = table.down(.fnOnly, resolvedAction: nil)
        XCTAssertNil(command)
    }

    func testDownWithNilActionRecordsNothingSoUpIsSuppressed() {
        _ = table.down(.fnOnly, resolvedAction: nil)
        // No down was recorded, so the up edge is an orphan and must be suppressed.
        XCTAssertNil(table.up(.fnOnly))
    }

    // MARK: - Fn chord up

    func testMatchingUpReturnsUpCommandAndClears() {
        _ = table.down(.fnShift, resolvedAction: .polish)
        let up = table.up(.fnShift)
        XCTAssertEqual(up, HotkeyRouteCommand(phase: .up, action: .polish, trigger: .anchor(.fnShift)))
        // Cleared — a second up for the same chord is now an orphan.
        XCTAssertNil(table.up(.fnShift))
    }

    func testOrphanUpWithoutPriorDownReturnsNil() {
        XCTAssertNil(table.up(.fnOnly))
    }

    // MARK: - Two distinct chords paired independently

    func testTwoDistinctChordsPairIndependently() {
        _ = table.down(.fnOnly, resolvedAction: .raw)
        _ = table.down(.fnShift, resolvedAction: .polish)

        let upShift = table.up(.fnShift)
        XCTAssertEqual(upShift, HotkeyRouteCommand(phase: .up, action: .polish, trigger: .anchor(.fnShift)))
        // The other chord's record is untouched.
        let upOnly = table.up(.fnOnly)
        XCTAssertEqual(upOnly, HotkeyRouteCommand(phase: .up, action: .raw, trigger: .anchor(.fnOnly)))
    }

    // MARK: - Right Option anchor (parallel cases)

    func testRightOptionAnchorDownWithActionRecordsAndReturnsDownCommand() {
        let command = table.down(.rightOptionOnly, resolvedAction: .askAnything)
        XCTAssertEqual(
            command,
            HotkeyRouteCommand(phase: .down, action: .askAnything, trigger: .anchor(.rightOptionOnly)))
    }

    func testRightOptionAnchorDownWithNilActionReturnsNil() {
        let command = table.down(.rightOptionOnly, resolvedAction: nil)
        XCTAssertNil(command)
    }

    func testRightOptionAnchorMatchingUpReturnsUpCommandAndClears() {
        _ = table.down(.rightOptionOnly, resolvedAction: .askAnything)
        let up = table.up(.rightOptionOnly)
        XCTAssertEqual(
            up,
            HotkeyRouteCommand(phase: .up, action: .askAnything, trigger: .anchor(.rightOptionOnly)))
        XCTAssertNil(table.up(.rightOptionOnly))
    }

    func testRightOptionAnchorOrphanUpReturnsNil() {
        XCTAssertNil(table.up(.rightOptionOnly))
    }
}
