import XCTest
@testable import ResponsayMac

@MainActor
final class ElectronAXUnlockTests: XCTestCase {
    private var requestedPIDs: [pid_t] = []
    private var trusted = true

    private func makeUnlock() -> ElectronAXUnlock {
        ElectronAXUnlock(
            isTrusted: { self.trusted },
            setAttribute: { pid, _ in self.requestedPIDs.append(pid) })
    }

    func testRequestsAttributeOncePerPID() {
        let unlock = makeUnlock()
        unlock.request(pid: 42, bundleID: "com.anthropic.claudefordesktop")
        unlock.request(pid: 42, bundleID: "com.anthropic.claudefordesktop")
        XCTAssertEqual(requestedPIDs, [42])
    }

    func testEachNewPIDGetsItsOwnRequest() {
        let unlock = makeUnlock()
        unlock.request(pid: 42, bundleID: "com.anthropic.claudefordesktop")
        unlock.request(pid: 43, bundleID: "com.anthropic.claudefordesktop")  // same app relaunched
        XCTAssertEqual(requestedPIDs, [42, 43])
    }

    func testUntrustedRequestIsSkippedAndNotBurned() {
        trusted = false
        let unlock = makeUnlock()
        unlock.request(pid: 42, bundleID: "com.anthropic.claudefordesktop")
        XCTAssertEqual(requestedPIDs, [])
        // The pid must stay eligible: once 辅助功能 is granted later, the same app still unlocks.
        trusted = true
        unlock.request(pid: 42, bundleID: "com.anthropic.claudefordesktop")
        XCTAssertEqual(requestedPIDs, [42])
    }

    func testNilTargetIsIgnored() {
        let unlock = makeUnlock()
        unlock.request(for: nil)
        XCTAssertEqual(requestedPIDs, [])
    }
}
