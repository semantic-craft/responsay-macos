import XCTest
@testable import ResponsayMac

final class ASRFallbackTests: XCTestCase {
    func testAppleIsAlwaysReady() {
        XCTAssertTrue(ASRFallback.isReady(.apple, isInstalled: { _ in false }, cloudHasKey: { _ in false }))
    }

    func testOfflineEngineReadyOnlyWhenInstalled() {
        XCTAssertFalse(ASRFallback.isReady(.fireRedASR2AEDLocal, isInstalled: { _ in false }, cloudHasKey: { _ in false }))
        XCTAssertTrue(ASRFallback.isReady(.fireRedASR2AEDLocal, isInstalled: { _ in true }, cloudHasKey: { _ in false }))
        XCTAssertTrue(ASRFallback.isReady(.funAsrNanoLocal, isInstalled: { _ in true }, cloudHasKey: { _ in false }))
    }

    func testCloudEngineReadyOnlyWithKey() {
        XCTAssertFalse(ASRFallback.isReady(.cloudOpenAI, isInstalled: { _ in true }, cloudHasKey: { _ in false }))
        XCTAssertTrue(ASRFallback.isReady(.cloudOpenAI, isInstalled: { _ in true }, cloudHasKey: { _ in true }))
    }

    func testUnusableSelectionFallsBackToApple() {
        // Offline model not downloaded → Apple.
        XCTAssertEqual(
            ASRFallback.effectiveEngine(.qwen3LocalASR, isInstalled: { _ in false }, cloudHasKey: { _ in false }),
            .apple)
        // Cloud engine missing key → Apple.
        XCTAssertEqual(
            ASRFallback.effectiveEngine(.cloudMimo, isInstalled: { _ in true }, cloudHasKey: { _ in false }),
            .apple)
    }

    func testReadySelectionIsHonored() {
        XCTAssertEqual(
            ASRFallback.effectiveEngine(.fireRedASR2AEDLocal, isInstalled: { _ in true }, cloudHasKey: { _ in false }),
            .fireRedASR2AEDLocal)
        XCTAssertEqual(
            ASRFallback.effectiveEngine(.cloudQwenASRFlashRealtime, isInstalled: { _ in false }, cloudHasKey: { _ in true }),
            .cloudQwenASRFlashRealtime)
        XCTAssertEqual(
            ASRFallback.effectiveEngine(.apple, isInstalled: { _ in false }, cloudHasKey: { _ in false }),
            .apple)
    }

    func testOfflineSpecMapping() {
        XCTAssertEqual(ASRFallback.offlineSpec(for: .sensevoiceLocal)?.id, LocalModelSpec.senseVoiceSmall.id)
        XCTAssertEqual(ASRFallback.offlineSpec(for: .funAsrNanoLocal)?.id, LocalModelSpec.funAsrNano.id)
        XCTAssertNil(ASRFallback.offlineSpec(for: .apple))
        XCTAssertNil(ASRFallback.offlineSpec(for: .cloudOpenAI))
    }
}
