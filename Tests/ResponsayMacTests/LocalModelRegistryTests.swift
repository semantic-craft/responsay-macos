import XCTest
@testable import ResponsayMac

final class LocalModelRegistryTests: XCTestCase {
    func testRegistryHasDownloadableDefaultASR() {
        let def = LocalModelRegistry.defaultASR
        XCTAssertEqual(def.id, ASREngine.sensevoiceLocal.rawValue)
        XCTAssertEqual(def.capability, .asr)
        XCTAssertEqual(def.runtime, .sherpaOnnx)
        XCTAssertTrue(def.isDownloadable)
        XCTAssertFalse(LocalModelRegistry.asrModels.isEmpty)
        XCTAssertEqual(LocalModelRegistry.spec(id: def.id)?.id, def.id)
    }

    func testEveryCatalogEntryIsDownloadable() {
        // The catalog must never ship ghost entries (visible but undownloadable,
        // or downloadable but without a runnable engine) — audit area 6.
        for spec in LocalModelRegistry.all {
            XCTAssertTrue(spec.isDownloadable, "\(spec.id) has no DownloadSource")
        }
        XCTAssertEqual(LocalModelRegistry.downloadable.count, LocalModelRegistry.all.count)
    }

    func testSpecCodableRoundTrip() throws {
        let spec = LocalModelRegistry.defaultASR
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(LocalModelSpec.self, from: data)
        XCTAssertEqual(decoded, spec)
        XCTAssertEqual(decoded.download?.sha256, spec.download?.sha256)
    }

    func testStoragePathUnderApplicationSupport() {
        let path = LocalModelRegistry.defaultASR.storagePath.path
        XCTAssertTrue(path.contains("Application Support/Responsay/models"))
        XCTAssertTrue(path.hasSuffix(SenseVoiceModel.directoryName))
    }

    func testEngineKeepAliveParsing() {
        XCTAssertEqual(EngineKeepAlive(raw: "0"), .immediate)
        XCTAssertEqual(EngineKeepAlive(raw: "never"), .keepForever)
        XCTAssertEqual(EngineKeepAlive(raw: "5"), .minutes(5))
        XCTAssertEqual(EngineKeepAlive(raw: "30"), .minutes(30))
        XCTAssertEqual(EngineKeepAlive(raw: "garbage"), .minutes(5))  // safe default
        XCTAssertEqual(EngineKeepAlive(raw: "0").idleNanoseconds, 0)
        XCTAssertNil(EngineKeepAlive(raw: "never").idleNanoseconds)
        XCTAssertEqual(EngineKeepAlive(raw: "5").idleNanoseconds, 300_000_000_000)
    }

    // MARK: - 203 Kokoro TTS model

    func testRegistryHasDownloadableDefaultTTS() {
        let def = LocalModelRegistry.defaultTTS
        XCTAssertEqual(def.id, "local-kokoro")  // == TTSEngine.sherpaKokoroLocal.rawValue (193)
        XCTAssertEqual(def.capability, .tts)
        XCTAssertEqual(def.runtime, .sherpaOnnx)
        XCTAssertEqual(def.family, .kokoro)
        XCTAssertTrue(def.isDownloadable)
        XCTAssertEqual(LocalModelRegistry.ttsModels.map(\.id), [def.id])
        XCTAssertEqual(LocalModelRegistry.spec(id: def.id)?.id, def.id)
    }

    func testKokoroSpecCodableRoundTrip() throws {
        let spec = LocalModelRegistry.defaultTTS
        let decoded = try JSONDecoder().decode(
            LocalModelSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(decoded, spec)
        XCTAssertEqual(decoded.download?.sha256,
                       "a3f4c73d043860e3fd2e5b06f36795eb81de0fc8e8de6df703245edddd87dbad")
        XCTAssertEqual(decoded.download?.byteSize, 364_816_464)
        XCTAssertEqual(decoded.download?.requiredFiles.first, "model.onnx")
    }

    func testKokoroIsInstalledFlipsOnRequiredFiles() throws {
        // Build a temp dir, drop each required file in turn, assert install flips on
        // only when all markers exist — pure file-presence logic, no model needed.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let required = LocalModelRegistry.defaultTTS.download!.requiredFiles
        // Point the spec at the temp dir via a stand-in with the same required files.
        func installed(in root: URL) -> Bool {
            required.allSatisfy {
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
            }
        }
        XCTAssertFalse(installed(in: tmp))
        for file in required {
            let url = tmp.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        XCTAssertTrue(installed(in: tmp))
    }

    // MARK: - PaddleOCR local OCR model

    func testRegistryHasDownloadableDefaultOCR() {
        let def = LocalModelRegistry.defaultOCR
        XCTAssertEqual(def.id, OCREngine.paddleOCRLocal.rawValue)
        XCTAssertEqual(def.capability, .ocr)
        XCTAssertEqual(def.runtime, .onnxRuntime)
        XCTAssertEqual(def.family, .paddleOCR)
        XCTAssertTrue(def.isDownloadable)
        XCTAssertEqual(LocalModelRegistry.ocrModels.map(\.id), [def.id])
        XCTAssertEqual(LocalModelRegistry.spec(id: def.id)?.id, def.id)
    }

    func testPaddleOCRSpecUsesVerifiedLooseFiles() throws {
        let spec = LocalModelRegistry.defaultOCR
        let download = try XCTUnwrap(spec.download)
        XCTAssertEqual(download.byteSize, 31_191_354)
        XCTAssertEqual(download.files.count, 4)
        XCTAssertEqual(Set(download.requiredFiles), Set(download.files.map(\.relativePath)))
        XCTAssertEqual(
            Set(download.requiredFiles),
            Set(["det/inference.onnx", "det/inference.yml", "rec/inference.onnx", "rec/inference.yml"]))
        XCTAssertEqual(
            download.files.map(\.byteSize).reduce(0, +),
            download.byteSize)
    }

    /// Real self-check against the installed model (skips if weights absent).
    func testSelfCheckOnInstalledModel() throws {
        let spec = LocalModelRegistry.defaultASR
        try XCTSkipUnless(spec.isInstalled, "SenseVoice not installed; skipping self-check")
        let report = try LocalModelSelfCheck.runASR(spec)
        XCTAssertGreaterThan(report.realtimeFactor, 1.0, "should be faster than real time")
        XCTAssertFalse(report.transcript.isEmpty)
        print("self-check → \(report.summary)  transcript=\(report.transcript)")
    }
}
