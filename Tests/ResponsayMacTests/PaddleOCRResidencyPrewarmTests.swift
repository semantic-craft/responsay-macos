import XCTest
@testable import ResponsayMac

@MainActor
final class PaddleOCRResidencyPrewarmTests: XCTestCase {
    private final class FakeController: LocalEngineResidencyControllable {
        var isCapturing = false
        var backgroundPreloadCount = 0
        var unloadCount = 0
        func preloadEngine() throws {}
        func preloadEngineInBackground() { backgroundPreloadCount += 1 }
        func unloadEngine() { unloadCount += 1 }
    }

    func testResidencyIDMapsOnlyLocalPaddleOCR() {
        XCTAssertEqual(
            PaddleOCRResidencyPrewarm.residencyID(for: OCREngine.paddleOCRLocal.rawValue),
            LocalModelRegistry.defaultOCR.id)
        XCTAssertNil(PaddleOCRResidencyPrewarm.residencyID(for: OCREngine.appleVision.rawValue))
        XCTAssertNil(PaddleOCRResidencyPrewarm.residencyID(for: OCREngine.mistral.rawValue))
        XCTAssertNil(PaddleOCRResidencyPrewarm.residencyID(for: OCREngine.baidu.rawValue))
    }

    func testOnSelectionPrewarmsPaddleOCR() {
        let residency = LocalEngineResidency()
        let target = FakeController()
        residency.register(target, id: LocalModelRegistry.defaultOCR.id)

        PaddleOCRResidencyPrewarm.onSelection(OCREngine.paddleOCRLocal.rawValue, residency: residency)

        XCTAssertEqual(target.backgroundPreloadCount, 1)
    }

    func testOnSelectionAwayFromPaddleReleasesOnlyOCR() {
        let residency = LocalEngineResidency()
        let ocr = FakeController()
        let asr = FakeController()
        let ocrID = LocalModelRegistry.defaultOCR.id
        let asrID = LocalModelSpec.senseVoiceSmall.id
        residency.register(ocr, id: ocrID)
        residency.register(asr, id: asrID)
        residency.setResident(ocrID, true)
        residency.setResident(asrID, true)

        PaddleOCRResidencyPrewarm.onSelection(OCREngine.appleVision.rawValue, residency: residency)

        XCTAssertEqual(ocr.unloadCount, 1)
        XCTAssertEqual(asr.unloadCount, 0)
    }
}
