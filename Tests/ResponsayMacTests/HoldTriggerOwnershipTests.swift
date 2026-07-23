import XCTest
@testable import ResponsayMac

final class HoldTriggerOwnershipTests: XCTestCase {

    private let triggerA: HotkeyTrigger = .anchor(.fnOnly)
    private let triggerB: HotkeyTrigger = .anchor(.fnShift)

    private var ownership = HoldTriggerOwnership()

    override func setUp() {
        super.setUp()
        ownership = HoldTriggerOwnership()
    }

    // MARK: - Acquire then release the same trigger

    func testAcquireThenReleaseSameTriggerSucceeds() {
        ownership.acquire(triggerA)
        XCTAssertTrue(ownership.release(triggerA))
        XCTAssertNil(ownership.owner)
    }

    // MARK: - Release by a foreign trigger fails and keeps the owner

    func testReleaseByForeignTriggerFailsAndKeepsOwner() {
        ownership.acquire(triggerA)
        XCTAssertFalse(ownership.release(triggerB))
        XCTAssertEqual(ownership.owner, triggerA)
    }

    // MARK: - Release with no owner

    func testReleaseWithNoOwnerFails() {
        XCTAssertFalse(ownership.release(triggerA))
        XCTAssertNil(ownership.owner)
    }

    // MARK: - Re-acquire replaces the owner

    func testReacquireReplacesOwner() {
        ownership.acquire(triggerA)
        ownership.acquire(triggerB)
        // The newest acquirer owns the session.
        XCTAssertTrue(ownership.release(triggerB))
        // The previous owner can no longer release it.
        XCTAssertFalse(ownership.release(triggerA))
    }
}
