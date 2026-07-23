import XCTest
@testable import ResponsayMac

/// 方案 A simultaneous tap+hold gesture classifier (issue 407). The classifier is the only pure
/// seam; the NSEvent/audio wiring in `CaptureSpeechController` is device-verified (issue 411).
final class TapHoldGestureClassifierTests: XCTestCase {

    private let threshold: TimeInterval = 0.25

    // MARK: - Press edge

    func testDownWhileIdleBegins() {
        XCTAssertEqual(TapHoldGestureClassifier.onDown(isListening: false), .begin)
    }

    func testDownWhileListeningStopsHandsFree() {
        // A second tap of an already-listening (hands-free) session stops it.
        XCTAssertEqual(TapHoldGestureClassifier.onDown(isListening: true), .stopHandsFree)
    }

    // MARK: - Release edge — hold vs tap

    func testHeldPastThresholdStopsPushToTalk() {
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: 0.40, threshold: threshold, isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .stopPushToTalk)
    }

    func testShortTapReleaseKeepsListening() {
        // Released before the threshold → a tap; the session stays listening (hands-free), so
        // the release is a no-op (`ignore`), not a stop.
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: 0.10, threshold: threshold, isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .ignore)
    }

    func testReleaseExactlyAtThresholdIsHold() {
        // Boundary: at exactly the threshold the press counts as a hold (>= threshold).
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: threshold, threshold: threshold, isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .stopPushToTalk)
    }

    func testReleaseJustBelowThresholdIsTap() {
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: threshold - 0.001, threshold: threshold, isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .ignore)
    }

    // MARK: - Release edge — per-function gesture override (issue 408)

    func testTapOnlyKeepsListeningEvenWhenHeldPastThreshold() {
        // tapOnly = pure toggle: a long hold's release must NOT stop the session (it would
        // under `both`); only the next tap stops it.
        let gesture = TapHoldGestureClassifier.onUp(
            gesture: .tapOnly, heldFor: 0.80, threshold: threshold,
            isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .ignore)
    }

    func testHoldOnlyStopsEvenOnAShortRelease() {
        // holdOnly = pure push-to-talk: any release stops, even a quick one that would be a tap
        // under `both`.
        let gesture = TapHoldGestureClassifier.onUp(
            gesture: .holdOnly, heldFor: 0.05, threshold: threshold,
            isListening: true, ownsSession: true)
        XCTAssertEqual(gesture, .stopPushToTalk)
    }

    func testBothUsesDurationUnderExplicitOverride() {
        // The default `both` is duration-based whether passed explicitly or by default.
        XCTAssertEqual(
            TapHoldGestureClassifier.onUp(
                gesture: .both, heldFor: 0.40, threshold: threshold,
                isListening: true, ownsSession: true),
            .stopPushToTalk)
        XCTAssertEqual(
            TapHoldGestureClassifier.onUp(
                gesture: .both, heldFor: 0.10, threshold: threshold,
                isListening: true, ownsSession: true),
            .ignore)
    }

    func testGuardsHoldRegardlessOfOverride() {
        // The listening / ownership guards win over any gesture override: a holdOnly release of
        // a session this trigger does not own (or that is not listening) must never stop it.
        XCTAssertEqual(
            TapHoldGestureClassifier.onUp(
                gesture: .holdOnly, heldFor: 0.80, threshold: threshold,
                isListening: false, ownsSession: true),
            .ignore)
        XCTAssertEqual(
            TapHoldGestureClassifier.onUp(
                gesture: .holdOnly, heldFor: 0.80, threshold: threshold,
                isListening: true, ownsSession: false),
            .ignore)
    }

    // MARK: - Release edge — guards

    func testReleaseWhenNotListeningIsIgnored() {
        // Nothing is recording (e.g. a tap already stopped it on its key-down) → ignore.
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: 0.40, threshold: threshold, isListening: false, ownsSession: true)
        XCTAssertEqual(gesture, .ignore)
    }

    func testReleaseByNonOwnerIsIgnored() {
        // A foreign / stale key-up must not cut a session this trigger did not start.
        let gesture = TapHoldGestureClassifier.onUp(
            heldFor: 0.40, threshold: threshold, isListening: true, ownsSession: false)
        XCTAssertEqual(gesture, .ignore)
    }
}
