import XCTest
@testable import ResponsayMac

/// 280 — the onboarding 基础层 step's aggregate over the two model downloads.
final class BasicsLayerStatusTests: XCTestCase {
    func testAllInstalled() {
        let s = BasicsLayerStatus(states: [.installed, .installed])
        XCTAssertTrue(s.allInstalled)
        XCTAssertFalse(s.anyBusy)
        XCTAssertNil(s.firstFailure)
        XCTAssertEqual(s.fraction, 1, accuracy: 0.0001)
    }

    func testHalfwayDownload_blendsFractions() {
        let s = BasicsLayerStatus(states: [.installed, .downloading(0.5)])
        XCTAssertFalse(s.allInstalled)
        XCTAssertTrue(s.anyBusy)
        XCTAssertEqual(s.fraction, 0.75, accuracy: 0.0001)
    }

    func testFailure_surfacesFirstMessage_andStopsBeingBusy() {
        let s = BasicsLayerStatus(states: [.failed("网络中断"), .notInstalled])
        XCTAssertFalse(s.allInstalled)
        XCTAssertFalse(s.anyBusy)
        XCTAssertEqual(s.firstFailure, "网络中断")
    }

    func testVerifyingExtracting_countAsBusyNearDone() {
        let s = BasicsLayerStatus(states: [.verifying, .extracting])
        XCTAssertTrue(s.anyBusy)
        XCTAssertEqual(s.fraction, 0.97, accuracy: 0.0001)
    }

    func testNotStarted_isIdleZero() {
        let s = BasicsLayerStatus(states: [.notInstalled, .notInstalled])
        XCTAssertFalse(s.allInstalled)
        XCTAssertFalse(s.anyBusy)
        XCTAssertEqual(s.fraction, 0, accuracy: 0.0001)
    }

    func testEmpty_isInert() {
        let s = BasicsLayerStatus(states: [])
        XCTAssertFalse(s.allInstalled)
        XCTAssertEqual(s.fraction, 0)
    }
}
