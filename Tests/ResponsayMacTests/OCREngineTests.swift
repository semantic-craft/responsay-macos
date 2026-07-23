import XCTest
@testable import ResponsayMac
import ResponsayCore

/// OCR engine selection (Settings › 图片识别 picker, persisted under `ocrEngine`). Pure default
/// resolution — no screen, no Keychain. Mirrors `ASREngineMigrationTests`.
final class OCREngineTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OCREngineTests-\(UUID().uuidString)")!
    }

    func testDefaultIsAppleVisionWhenUnset() {
        XCTAssertEqual(OCREngine.selected(defaults: freshDefaults()), .appleVision)
    }

    func testSelectedReadsStoredRawValue() {
        let defaults = freshDefaults()
        defaults.set("mistral-ocr", forKey: OCREngine.defaultsKey)
        XCTAssertEqual(OCREngine.selected(defaults: defaults), .mistral)
    }

    func testUnknownRawFallsBackToAppleVision() {
        let defaults = freshDefaults()
        defaults.set("totally-unknown-engine", forKey: OCREngine.defaultsKey)
        XCTAssertEqual(OCREngine.selected(defaults: defaults), .appleVision)
    }

    func testBlankRawFallsBackToAppleVision() {
        let defaults = freshDefaults()
        defaults.set("   ", forKey: OCREngine.defaultsKey)
        XCTAssertEqual(OCREngine.selected(defaults: defaults), .appleVision)
    }

    /// The picker raw values MUST equal the concrete providers' ids, or `RoutedOCRProvider` would
    /// resolve the wrong engine.
    func testRawValuesMatchProviderIDs() {
        XCTAssertEqual(OCREngine.appleVision.rawValue, AppleVisionOCRProvider().id)
        XCTAssertEqual(OCREngine.paddleOCRLocal.rawValue, PaddleOCRProvider.engineID)
        XCTAssertEqual(OCREngine.mistral.rawValue, MistralOCRProvider.engineID)
        XCTAssertEqual(OCREngine.baidu.rawValue, BaiduOCRProvider.engineID)
    }

    func testSelectableCases() {
        XCTAssertEqual(OCREngine.selectableCases, [.appleVision, .paddleOCRLocal, .mistral, .baidu])
    }

    func testLocalFlag() {
        XCTAssertTrue(OCREngine.appleVision.isLocal)
        XCTAssertTrue(OCREngine.paddleOCRLocal.isLocal)
        XCTAssertFalse(OCREngine.mistral.isLocal)
        XCTAssertFalse(OCREngine.baidu.isLocal)
    }
}
