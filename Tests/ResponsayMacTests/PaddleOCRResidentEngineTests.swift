import CoreGraphics
import XCTest
@testable import ResponsayMac
import ResponsayCore

@MainActor
final class PaddleOCRResidentEngineTests: XCTestCase {
    private struct StubProvider: OCRProvider {
        let id = PaddleOCRProvider.engineID
        let displayName = "Stub Paddle"

        func recognize(_ image: CGImage) async throws -> OCRResult {
            OCRResult(
                regions: [OCRRegion(text: "hello", boundingBox: .zero, confidence: 1)],
                languages: ["en"])
        }
    }

    func testPreloadAndUnloadMirrorResidencyState() throws {
        let spec = try makeInstalledSpec()
        let residency = LocalEngineResidency()
        let engine = PaddleOCRResidentEngine(
            spec: spec, residency: residency, makeProvider: { StubProvider() })

        XCTAssertFalse(residency.canControl(spec.id))
        try engine.preloadEngine()
        XCTAssertTrue(residency.canControl(spec.id))
        XCTAssertTrue(residency.isResident(spec.id))

        engine.unloadEngine()
        XCTAssertFalse(residency.isResident(spec.id))
    }

    func testResidentProviderLoadsThroughController() async throws {
        let spec = try makeInstalledSpec()
        let residency = LocalEngineResidency()
        let engine = PaddleOCRResidentEngine(
            spec: spec, residency: residency, makeProvider: { StubProvider() })
        let provider = ResidentPaddleOCRProvider(engine: engine)

        let priorTTL = UserDefaults.standard.string(forKey: "localEngineTTL")
        UserDefaults.standard.set("never", forKey: "localEngineTTL")
        addTeardownBlock {
            if let priorTTL {
                UserDefaults.standard.set(priorTTL, forKey: "localEngineTTL")
            } else {
                UserDefaults.standard.removeObject(forKey: "localEngineTTL")
            }
        }

        let result = try await provider.recognize(Self.blankImage())

        XCTAssertEqual(result.text, "hello")
        XCTAssertFalse(engine.isCapturing)
        XCTAssertTrue(residency.isResident(spec.id))
    }

    private func makeInstalledSpec() throws -> LocalModelSpec {
        let id = "test-paddleocr-\(UUID().uuidString)"
        let spec = LocalModelSpec(
            id: id,
            displayName: "Test PaddleOCR",
            capability: .ocr,
            runtime: .onnxRuntime,
            family: .paddleOCR,
            languages: ["en"],
            qualityTier: "test",
            directoryName: id,
            expected: ExpectedMetrics(asrRealtimeFactor: nil, approxDiskBytes: 1),
            download: DownloadSource(
                urls: [URL(string: "https://example.com/model.tar.bz2")!],
                sha256: String(repeating: "0", count: 64),
                byteSize: 1,
                requiredFiles: ["model.onnx"]))
        try FileManager.default.createDirectory(
            at: spec.storagePath, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: spec.storagePath.appendingPathComponent("model.onnx"))
        addTeardownBlock { try? LocalModelDownloader.remove(spec) }
        return spec
    }

    private static func blankImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
