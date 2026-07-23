import XCTest
@testable import ResponsayMac
import ResponsayCore

@MainActor
final class ReadAloudTransactionManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsCenter.shared.clear()
    }

    override func tearDown() {
        DiagnosticsCenter.shared.clear()
        super.tearDown()
    }

    func testBeginSupersedesPreviousTransaction() {
        let manager = ReadAloudTransactionManager()
        let tx1 = manager.begin()
        let tx2 = manager.begin()

        XCTAssertNotEqual(tx1.requestID, tx2.requestID)
        XCTAssertFalse(manager.isCurrent(tx1, phase: "p"))
        XCTAssertTrue(manager.isCurrent(tx2, phase: "p"))
        XCTAssertEqual(manager.current, tx2)
    }

    func testClearDropsCurrentTransaction() {
        let manager = ReadAloudTransactionManager()
        let tx = manager.begin()

        manager.clear()

        XCTAssertNil(manager.current)
        XCTAssertFalse(manager.isCurrent(tx, phase: "p"))
    }

    func testStaleCallbackEmitsDiagnostic() async throws {
        let manager = ReadAloudTransactionManager()
        let tx1 = manager.begin()
        _ = manager.begin()

        XCTAssertFalse(manager.isCurrent(tx1, phase: "synthDone"))

        // Diag records into DiagnosticsCenter via a @MainActor Task, so poll until it drains.
        var recorded = false
        for _ in 0..<50 {
            if DiagnosticsCenter.shared.events.contains(where: {
                $0.title == "staleCallbackIgnored"
                    && $0.fields["oldRequestID"] == tx1.requestID.uuidString
            }) {
                recorded = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(recorded)
    }
}
