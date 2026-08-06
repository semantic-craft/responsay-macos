import XCTest
@testable import ResponsayMac

@MainActor
final class HotkeyActionRouterTests: XCTestCase {
    private let trigger = HotkeyTrigger.anchor(.fnOnly)

    func testCaptureActionRoutesToCapture() {
        let host = Host()
        let router = host.makeRouter()

        router.handle(.down, action: .raw, trigger: trigger)
        router.handle(.up, action: .raw, trigger: trigger)

        XCTAssertEqual(host.beginCaptureActions, [.raw])
        XCTAssertEqual(host.finishCaptureCount, 1)
    }

    // Regression: a tap of a capture key always captures — a live selection never diverts it.
    // The old selection-voice-command hijack is gone; selection commands are 任意提问 / 划词菜单.
    func testCaptureTapAlwaysCapturesEvenWithSelectionPresent() {
        let host = Host()
        let router = host.makeRouter()

        router.handle(.down, action: .expressInEnglish, trigger: trigger)
        router.handle(.up, action: .expressInEnglish, trigger: trigger)

        XCTAssertEqual(host.beginCaptureActions, [.expressInEnglish])
        XCTAssertEqual(host.finishCaptureCount, 1)
    }

    func testFixedSelectionActionRoutesToHandler() {
        let host = Host()
        let router = host.makeRouter()

        router.handle(.down, action: .rewriteSelection, trigger: trigger)
        router.handle(.up, action: .rewriteSelection, trigger: trigger)

        XCTAssertEqual(host.rewriteSelectionCount, 1)
        XCTAssertEqual(host.beginCaptureActions, [])
    }

    func testSelectionMenuRoutesToShowSelectionMenu() {
        let host = Host()
        let router = host.makeRouter()

        router.handle(.down, action: .selectionMenu, trigger: trigger)
        router.handle(.up, action: .selectionMenu, trigger: trigger)

        XCTAssertEqual(host.showSelectionMenuCount, 1)
        XCTAssertEqual(host.beginCaptureActions, [])
    }

    func testAskAnythingRoutesToAskAnything() {
        let host = Host()
        let router = host.makeRouter()

        router.handle(.down, action: .askAnything, trigger: trigger)
        router.handle(.up, action: .askAnything, trigger: trigger)

        XCTAssertEqual(host.beginAskAnythingCount, 1)
        XCTAssertEqual(host.finishAskAnythingCount, 1)
    }

    @MainActor
    private final class Host {
        var beginCaptureActions: [ShortcutAction] = []
        var finishCaptureCount = 0
        var rewriteSelectionCount = 0
        var showSelectionMenuCount = 0
        var readAloudSelectionCount = 0
        var beginAskAnythingCount = 0
        var finishAskAnythingCount = 0

        func makeRouter() -> HotkeyActionRouter {
            HotkeyActionRouter(handlers: HotkeyActionHandlers(
                isHoldToTalkEnabled: { true },
                beginCapture: { action, _ in self.beginCaptureActions.append(action) },
                finishCurrentHotkeyAction: { _ in self.finishCaptureCount += 1 },
                rewriteSelection: { self.rewriteSelectionCount += 1 },
                translateSelection: {},
                snapOCR: {},
                snapTextOCR: {},
                snapImageCopy: {},
                showSelectionMenu: { self.showSelectionMenuCount += 1 },
                readAloudSelection: { self.readAloudSelectionCount += 1 },
                beginAskAnything: { _ in self.beginAskAnythingCount += 1 },
                finishAskAnything: { _ in self.finishAskAnythingCount += 1 },
                openApp: {},
                openSettings: {},
                confirmInsert: {}))
        }
    }
}
