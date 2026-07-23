import XCTest
@testable import ResponsayMac

/// `StateOrchestrator` owns the OS-event lifecycle interrupts (defaults-change / sleep / wake /
/// Esc) extracted from `CaptureController.start()`. The `handle*` methods are plain forwarders to
/// injected closures, so they're unit-testable without NSNotification / NSEvent registration.
@MainActor
final class StateOrchestratorTests: XCTestCase {
    @MainActor
    private final class Host {
        var reSyncCalls = 0
        var cancelCalls = 0
        var escapeCalls = 0
        /// Records the order effects fire, so we can assert wake re-syncs BEFORE it cancels.
        private(set) var order: [String] = []

        func makeOrchestrator() -> StateOrchestrator {
            StateOrchestrator(
                reSyncHotkeys: {
                    self.reSyncCalls += 1
                    self.order.append("reSync")
                },
                cancelCapture: {
                    self.cancelCalls += 1
                    self.order.append("cancel")
                },
                handleEscape: {
                    self.escapeCalls += 1
                    self.order.append("escape")
                })
        }

        var recordedOrder: [String] { order }
    }

    func testDefaultsChangedReSyncsHotkeys() {
        let host = Host()

        host.makeOrchestrator().handleDefaultsChanged()

        XCTAssertEqual(host.reSyncCalls, 1)
        XCTAssertEqual(host.cancelCalls, 0)
        XCTAssertEqual(host.escapeCalls, 0)
    }

    func testSleepCancelsCapture() async {
        let host = Host()

        await host.makeOrchestrator().handleSleep()

        XCTAssertEqual(host.cancelCalls, 1)
        XCTAssertEqual(host.reSyncCalls, 0)
        XCTAssertEqual(host.escapeCalls, 0)
    }

    func testWakeReSyncsThenCancels() async {
        let host = Host()

        await host.makeOrchestrator().handleWake()

        XCTAssertEqual(host.reSyncCalls, 1)
        XCTAssertEqual(host.cancelCalls, 1)
        // STATE-SLEEP-004: re-arm the Fn monitor BEFORE cancelling a stranded session.
        XCTAssertEqual(host.recordedOrder, ["reSync", "cancel"])
    }

    func testEscapeKeyWithEscapeKeyCodeFiresHandleEscape() async {
        let host = Host()

        await host.makeOrchestrator().handleEscapeKey(keyCode: 53)   // kVK_Escape

        XCTAssertEqual(host.escapeCalls, 1)
        XCTAssertEqual(host.cancelCalls, 0)
        XCTAssertEqual(host.reSyncCalls, 0)
    }

    func testEscapeKeyWithNonEscapeKeyCodeIsNoOp() async {
        let host = Host()

        await host.makeOrchestrator().handleEscapeKey(keyCode: 16)   // some other key

        XCTAssertEqual(host.escapeCalls, 0)
        XCTAssertEqual(host.cancelCalls, 0)
        XCTAssertEqual(host.reSyncCalls, 0)
    }
}
