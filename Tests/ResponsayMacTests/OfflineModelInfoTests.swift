import XCTest
@testable import ResponsayMac

final class OfflineModelInfoTests: XCTestCase {
    /// Every selectable offline ASR engine (the three downloadable models + Apple)
    /// exposes a non-empty summary / vendor / highlights triple (#388).
    func testEverySelectableOfflineEngineHasInfo() {
        let offline: [ASREngine] = [
            .funAsrNanoLocal, .qwen3LocalASR, .sensevoiceLocal, .apple,
        ]
        for engine in offline {
            let info = try? XCTUnwrap(engine.offlineModelInfo, "\(engine.rawValue) missing offline info")
            XCTAssertFalse(info?.vendor.isEmpty ?? true, "\(engine.rawValue) missing vendor")
            XCTAssertFalse(info?.summary.isEmpty ?? true, "\(engine.rawValue) missing summary")
            XCTAssertFalse(info?.highlights.isEmpty ?? true, "\(engine.rawValue) missing highlights")
        }
        // Sanity check the system-engine vendor mapping.
        XCTAssertEqual(ASREngine.apple.offlineModelInfo?.vendor, "Apple")
    }

    /// Cloud engines carry no offline-model info (their metadata is the provider catalog).
    func testCloudEnginesHaveNoOfflineInfo() {
        for engine in [
            ASREngine.cloudQwenASRFlashRealtime,
            .cloudOpenAI, .cloudMimo, .customOpenAI,
        ] {
            XCTAssertNil(engine.offlineModelInfo, "\(engine.rawValue) should have no offline info")
        }
    }

    /// The downloadable ASR specs resolve info via LocalModelSpec; the punctuation model now
    /// carries provenance too (surfaced in 设置›语音识别). Only TTS (Kokoro) has none.
    func testDownloadableASRSpecsResolveInfo() {
        XCTAssertNotNil(LocalModelSpec.funAsrNano.offlineModelInfo)
        XCTAssertNotNil(LocalModelSpec.qwen3ASR.offlineModelInfo)
        XCTAssertNotNil(LocalModelSpec.senseVoiceSmall.offlineModelInfo)
        XCTAssertNil(LocalModelSpec.kokoroMultiLangV1_1.offlineModelInfo)
        // 标点模型现在带出处（CT-Transformer / sherpa-onnx / FunASR-达摩院）。
        let punct = LocalModelSpec.ctTransformerPunctZhEn.offlineModelInfo
        XCTAssertNotNil(punct)
        XCTAssertTrue(punct?.vendor.contains("CT-Transformer") ?? false)
    }
}
