import CoreGraphics
import XCTest
@testable import ResponsayMac
import ResponsayCore

/// `RoutedOCRProvider` resolution table: engine choice + injected key reader → concrete provider.
/// A cloud engine missing its key(s) falls back to Apple Vision (snap still works on-device). Pure —
/// the injected `keyReader` stands in for the Keychain, so no real secrets are touched.
@MainActor
final class RoutedOCRProviderTests: XCTestCase {

    private func reader(_ map: [String: String]) -> (String) -> String? { { map[$0] } }

    private struct StubOCRProvider: OCRProvider {
        let id: String
        let displayName = "Stub OCR"

        func recognize(_ image: CGImage) async throws -> OCRResult {
            OCRResult(text: "", regions: [], languages: [])
        }
    }

    func testAppleVisionResolvesLocal() {
        let router = RoutedOCRProvider(engine: .appleVision, keyReader: { _ in nil })
        XCTAssertEqual(router.resolve().id, "apple-vision")
        XCTAssertFalse(router.willFallBackToLocal)
    }

    func testPaddleWithoutInstalledModelFallsBack() {
        let router = RoutedOCRProvider(
            engine: .paddleOCRLocal,
            keyReader: { _ in nil },
            paddleModelInstalled: { false },
            paddleProviderFactory: { StubOCRProvider(id: PaddleOCRProvider.engineID) })
        XCTAssertEqual(router.resolve().id, "apple-vision")
        XCTAssertTrue(router.willFallBackToLocal)
        XCTAssertFalse(router.resolvesToCloud)
        XCTAssertFalse(router.showsRecognitionProgress)
    }

    func testPaddleWithInstalledModelResolvesLocalPaddle() {
        let router = RoutedOCRProvider(
            engine: .paddleOCRLocal,
            keyReader: { _ in nil },
            paddleModelInstalled: { true },
            paddleProviderFactory: { StubOCRProvider(id: PaddleOCRProvider.engineID) })
        XCTAssertEqual(router.resolve().id, PaddleOCRProvider.engineID)
        XCTAssertFalse(router.willFallBackToLocal)
        XCTAssertFalse(router.resolvesToCloud)
        XCTAssertTrue(router.showsRecognitionProgress)
    }

    func testMistralWithKeyResolvesMistral() {
        let router = RoutedOCRProvider(
            engine: .mistral,
            keyReader: reader([OCRCredentialAccount.mistralAPIKey: "ms-key"]))
        XCTAssertEqual(router.resolve().id, "mistral-ocr")
        XCTAssertFalse(router.willFallBackToLocal)
    }

    func testMistralWithoutKeyFallsBack() {
        let router = RoutedOCRProvider(engine: .mistral, keyReader: { _ in nil })
        XCTAssertEqual(router.resolve().id, "apple-vision")
        XCTAssertTrue(router.willFallBackToLocal)
    }

    func testMistralWithBlankKeyFallsBack() {
        let router = RoutedOCRProvider(
            engine: .mistral,
            keyReader: reader([OCRCredentialAccount.mistralAPIKey: "   "]))
        XCTAssertEqual(router.resolve().id, "apple-vision")
        XCTAssertTrue(router.willFallBackToLocal)
    }

    func testBaiduWithBothKeysResolvesBaidu() {
        let router = RoutedOCRProvider(
            engine: .baidu,
            keyReader: reader([
                OCRCredentialAccount.baiduAPIKey: "ak",
                OCRCredentialAccount.baiduSecretKey: "sk",
            ]))
        XCTAssertEqual(router.resolve().id, "baidu-ocr")
        XCTAssertFalse(router.willFallBackToLocal)
    }

    func testBaiduMissingSecretFallsBack() {
        let router = RoutedOCRProvider(
            engine: .baidu,
            keyReader: reader([OCRCredentialAccount.baiduAPIKey: "ak"]))
        XCTAssertEqual(router.resolve().id, "apple-vision")
        XCTAssertTrue(router.willFallBackToLocal)
    }
}
