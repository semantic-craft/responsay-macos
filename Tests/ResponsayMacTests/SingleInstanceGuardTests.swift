import XCTest
@testable import ResponsayMac

/// INSTANCE-DOUBLE-001: a second instance must be detected so it can hand off and quit
/// instead of registering duplicate global hotkeys / a second mic engine.
final class SingleInstanceGuardTests: XCTestCase {
    func testNoDuplicateWhenOnlyOurPIDIsRunning() {
        XCTAssertFalse(SingleInstanceGuard.hasDuplicate(currentPID: 100, runningPIDs: [100]))
    }

    func testDuplicateWhenAnotherPIDSharesBundle() {
        XCTAssertTrue(SingleInstanceGuard.hasDuplicate(currentPID: 100, runningPIDs: [100, 200]))
    }

    func testDuplicateEvenWhenOurOwnPIDIsAbsentFromList() {
        // Defensive: a stale list missing our pid still counts another instance as a duplicate.
        XCTAssertTrue(SingleInstanceGuard.hasDuplicate(currentPID: 100, runningPIDs: [200]))
    }

    func testNoDuplicateForEmptyList() {
        XCTAssertFalse(SingleInstanceGuard.hasDuplicate(currentPID: 100, runningPIDs: []))
    }
}
