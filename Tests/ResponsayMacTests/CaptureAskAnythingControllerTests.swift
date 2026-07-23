import XCTest
@testable import ResponsayMac

/// 任意提问 (Ask Anything) from a normal hotkey is tap-to-run: a tap starts a hands-free
/// session and the next tap stops it. Hold-only is still supported when selection interaction
/// injects it directly.
@MainActor
final class CaptureAskAnythingControllerTests: XCTestCase {

    /// A scriptable stand-in for the live Voice-Assistant session: `start`/`stop` flip the
    /// listening flag and count calls; `clock`/`gesture` drive the tap-vs-hold classification.
    @MainActor
    private final class Host {
        var listening = false
        var startCalls = 0
        var stopCalls = 0
        var clock: TimeInterval = 0
        var gesture: TriggerGesture = .tapOnly

        func makeController() -> CaptureAskAnythingController {
            CaptureAskAnythingController(
                isListening: { self.listening },
                startSession: { self.startCalls += 1; self.listening = true },
                stopSession: { self.stopCalls += 1; self.listening = false },
                gestureProvider: { self.gesture },
                now: { self.clock })
        }
    }

    private let right = HotkeyTrigger.anchor(.rightOptionHyper)
    private let left = HotkeyTrigger.anchor(.fnOnly)

    // A quick tap starts a hands-free session that KEEPS listening on release (the bug:
    // it used to stop immediately). The next tap stops it.
    func testTapStartsHandsFreeAndStaysListening() {
        let host = Host()
        let controller = host.makeController()

        host.clock = 0
        controller.handleDown(trigger: right)
        XCTAssertEqual(host.startCalls, 1)
        XCTAssertTrue(host.listening)

        host.clock = 0.1   // released well under the hold threshold → a tap
        controller.handleUp(trigger: right)
        XCTAssertEqual(host.stopCalls, 0, "a tap release must not stop the session")
        XCTAssertTrue(host.listening)
    }

    func testSecondTapStopsHandsFreeSession() {
        let host = Host()
        let controller = host.makeController()

        controller.handleDown(trigger: right); host.clock = 0.1
        controller.handleUp(trigger: right)            // tap → still listening

        host.clock = 1.0
        controller.handleDown(trigger: right)          // second tap → stop
        XCTAssertEqual(host.startCalls, 1)
        XCTAssertEqual(host.stopCalls, 1)
        XCTAssertFalse(host.listening)
    }

    // Normal hotkeys are tap-only: even a long hold does not stop on release.
    func testLongHoldDoesNotStopOnReleaseByDefault() {
        let host = Host()
        let controller = host.makeController()

        host.clock = 0
        controller.handleDown(trigger: right)
        host.clock = 0.5
        controller.handleUp(trigger: right)
        XCTAssertEqual(host.startCalls, 1)
        XCTAssertEqual(host.stopCalls, 0)
        XCTAssertTrue(host.listening)
    }

    // A different binding's key-up cannot cut a session it never started.
    func testForeignKeyUpDoesNotStop() {
        let host = Host()
        let controller = host.makeController()

        controller.handleDown(trigger: right)          // right owns the session
        host.clock = 0.5
        controller.handleUp(trigger: left)             // foreign up
        XCTAssertEqual(host.stopCalls, 0)
        XCTAssertTrue(host.listening)
    }

    // Selection interaction can still inject holdOnly: a quick release then submits.
    func testHoldOnlyStopsEvenOnQuickRelease() {
        let host = Host()
        host.gesture = .holdOnly
        let controller = host.makeController()

        controller.handleDown(trigger: right)
        host.clock = 0.05
        controller.handleUp(trigger: right)
        XCTAssertEqual(host.stopCalls, 1)
    }

    // tapOnly override: a long hold's release never stops — only the next tap does.
    func testTapOnlyNeverStopsOnRelease() {
        let host = Host()
        host.gesture = .tapOnly
        let controller = host.makeController()

        controller.handleDown(trigger: right)
        host.clock = 1.0
        controller.handleUp(trigger: right)
        XCTAssertEqual(host.stopCalls, 0)
        XCTAssertTrue(host.listening)

        controller.handleDown(trigger: right)          // next tap stops
        XCTAssertEqual(host.stopCalls, 1)
    }
}
