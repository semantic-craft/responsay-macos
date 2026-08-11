import XCTest
@testable import ResponsayMac

/// LATENCY-MODELLOAD-001: selecting a local ASR engine prewarms it in the background and
/// releases any other resident local engine (openless preload-on-select + release-on-switch).
@MainActor
final class ASRResidencyPrewarmTests: XCTestCase {

    private final class FakeController: LocalEngineResidencyControllable {
        var isCapturing = false
        var backgroundPreloadCount = 0
        var unloadCount = 0
        func preloadEngine() throws {}
        func preloadEngineInBackground() { backgroundPreloadCount += 1 }
        func unloadEngine() { unloadCount += 1 }
    }

    func testResidencyIDMapsLocalEngines() {
        XCTAssertNotNil(ASRResidencyPrewarm.residencyID(for: "offline-sensevoice"))
        XCTAssertNotNil(ASRResidencyPrewarm.residencyID(for: "offline-qwen3-asr"))
        XCTAssertNotNil(ASRResidencyPrewarm.residencyID(for: "offline-funasr-nano"))
    }

    func testResidencyIDIsNilForCloudAndNonResidentEngines() {
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "cloud-qwen"))
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "apple"))
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "custom-openai"))
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "offline-zipformer-streaming"))
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "offline-fireredasr2-aed"))
        XCTAssertNil(ASRResidencyPrewarm.residencyID(for: "offline-qwen-asr"))  // #386: backend-era entry deleted
    }

    func testOnSelectionPrewarmsTargetAndReleasesOthers() {
        let residency = LocalEngineResidency()
        let target = FakeController()
        let other = FakeController()
        let targetID = ASRResidencyPrewarm.residencyID(for: "offline-qwen3-asr")!
        let otherID = ASRResidencyPrewarm.residencyID(for: "offline-sensevoice")!
        residency.register(target, id: targetID)
        residency.register(other, id: otherID)
        residency.setResident(otherID, true)   // a different local ASR engine is resident

        ASRResidencyPrewarm.onSelection("offline-qwen3-asr", residency: residency)

        XCTAssertEqual(target.backgroundPreloadCount, 1)   // selected engine prewarmed
        XCTAssertEqual(other.unloadCount, 1)               // the one we switched away from is freed
    }

    func testOnSelectionToCloudReleasesAllLocals() {
        let residency = LocalEngineResidency()
        let local = FakeController()
        let localID = ASRResidencyPrewarm.residencyID(for: "offline-sensevoice")!
        residency.register(local, id: localID)
        residency.setResident(localID, true)

        ASRResidencyPrewarm.onSelection("cloud-qwen", residency: residency)

        XCTAssertEqual(local.unloadCount, 1)
        XCTAssertEqual(local.backgroundPreloadCount, 0)   // nothing prewarmed for a cloud selection
    }

    func testASRSelectionDoesNotReleaseResidentOCR() {
        let residency = LocalEngineResidency()
        let asr = FakeController()
        let ocr = FakeController()
        let targetID = ASRResidencyPrewarm.residencyID(for: "offline-qwen3-asr")!
        let ocrID = LocalModelRegistry.defaultOCR.id
        residency.register(asr, id: targetID)
        residency.register(ocr, id: ocrID)
        residency.setResident(ocrID, true)

        ASRResidencyPrewarm.onSelection("offline-qwen3-asr", residency: residency)

        XCTAssertEqual(asr.backgroundPreloadCount, 1)
        XCTAssertEqual(ocr.unloadCount, 0)
    }
}
