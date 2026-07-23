import XCTest
@testable import ResponsayMac

@MainActor
final class CaptureEscapeControllerTests: XCTestCase {
    @MainActor
    private final class Host {
        var captureListening = false
        var askAnythingListening = false
        var captureCancelCalls = 0
        var askAnythingCancelCalls = 0

        func makeController() -> CaptureEscapeController {
            CaptureEscapeController(
                isCaptureListening: { self.captureListening },
                cancelCapture: {
                    self.captureCancelCalls += 1
                    self.captureListening = false
                },
                isAskAnythingListening: { self.askAnythingListening },
                cancelAskAnything: {
                    self.askAnythingCancelCalls += 1
                    self.askAnythingListening = false
                })
        }
    }

    func testEscapeCancelsRegularCaptureWhenListening() async {
        let host = Host()
        host.captureListening = true

        await host.makeController().handleEscape()

        XCTAssertEqual(host.captureCancelCalls, 1)
        XCTAssertEqual(host.askAnythingCancelCalls, 0)
        XCTAssertFalse(host.captureListening)
    }

    func testEscapeCancelsAskAnythingWhenListening() async {
        let host = Host()
        host.askAnythingListening = true

        await host.makeController().handleEscape()

        XCTAssertEqual(host.captureCancelCalls, 0)
        XCTAssertEqual(host.askAnythingCancelCalls, 1)
        XCTAssertFalse(host.askAnythingListening)
    }

    func testEscapeNoOpsWhenNothingIsListening() async {
        let host = Host()

        await host.makeController().handleEscape()

        XCTAssertEqual(host.captureCancelCalls, 0)
        XCTAssertEqual(host.askAnythingCancelCalls, 0)
    }

    func testRegularCaptureWinsIfStatesEverOverlap() async {
        let host = Host()
        host.captureListening = true
        host.askAnythingListening = true

        await host.makeController().handleEscape()

        XCTAssertEqual(host.captureCancelCalls, 1)
        XCTAssertEqual(host.askAnythingCancelCalls, 0)
    }
}
