import CoreGraphics
import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 070 — Snap & Translate orchestration: capture → recognize → classify, with the capturer and OCR
/// provider injected as stubs. Covers the four outcome branches the controller maps onto the view
/// -model (cancel / recognized / empty / failed) without a real screen, permission grant, or the
/// full `CaptureController`. This is the regression net the hard-instantiated `snapOCR()` lacked.
final class SnapOCRRunnerTests: XCTestCase {

    func testRun_returnsCancelled_whenCaptureYieldsNoImage() async {
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: false),
                                   provider: StubProvider(canned: .some(Self.text("ignored"))))
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .cancelled)   // Esc / capture failure → caller stays idle
    }

    func testRun_returnsRecognized_whenProviderReturnsText() async {
        let recognized = Self.text("本案标的额 120 万元")
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: true),
                                   provider: StubProvider(canned: recognized))
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .recognized(recognized))
    }

    func testRun_returnsEmpty_whenProviderRecognizesNothing() async {
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: true),
                                   provider: StubProvider(canned: OCRResult(regions: [], languages: ["zh-Hans"])))
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .empty)   // captured, but blank → controller shows guidance
    }

    func testRun_fallsBack_whenProviderRecognizesNothing() async {
        let fallbackResult = Self.text("fallback text")
        let runner = SnapOCRRunner(
            capturer: StubCapturer(returnsImage: true),
            provider: StubProvider(canned: OCRResult(regions: [], languages: ["auto"])),
            fallbackProvider: StubProvider(id: "fallback", canned: fallbackResult))
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .recognized(fallbackResult))
    }

    func testRun_fallsBack_whenProviderRecognizesOnlyOneCharacter() async {
        let fallbackResult = Self.text("fallback text")
        let runner = SnapOCRRunner(
            capturer: StubCapturer(returnsImage: true),
            provider: StubProvider(canned: Self.text("字")),
            fallbackProvider: StubProvider(id: "fallback", canned: fallbackResult))
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .recognized(fallbackResult))
    }

    func testRun_returnsFailed_whenProviderThrows() async {
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: true),
                                   provider: StubProvider(canned: nil))   // nil → throws
        let outcome = await runner.run()
        XCTAssertEqual(outcome, .failed("ocr boom"))
    }

    // MARK: - onRecognizing seam (cloud spinner fires only once there's a captured image to wait on)

    @MainActor
    func testRun_firesOnRecognizing_afterCapture() async {
        var fired = false
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: true),
                                   provider: StubProvider(canned: Self.text("x")))
        _ = await runner.run(onRecognizing: { fired = true })
        XCTAssertTrue(fired)
    }

    @MainActor
    func testRun_doesNotFireOnRecognizing_whenCancelled() async {
        var fired = false
        let runner = SnapOCRRunner(capturer: StubCapturer(returnsImage: false),
                                   provider: StubProvider(canned: Self.text("x")))
        let outcome = await runner.run(onRecognizing: { fired = true })
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(fired)   // no capture → no network → never show the spinner
    }

    // MARK: - Stubs (structs so they stay Sendable; the CGImage is built inside, never stored)

    private struct StubCapturer: ScreenRegionCapturer {
        let returnsImage: Bool
        func captureRegion() async -> CGImage? {
            returnsImage ? SnapOCRRunnerTests.blankImage() : nil
        }
    }

    private struct StubProvider: OCRProvider {
        var id = "stub"
        let displayName = "Stub"
        /// Canned result, or `nil` to throw (exercises the `.failed` branch).
        let canned: OCRResult?
        func recognize(_ image: CGImage) async throws -> OCRResult {
            guard let canned else { throw OCRError.recognitionFailed("ocr boom") }
            return canned
        }
    }

    private static func text(_ s: String) -> OCRResult {
        OCRResult(regions: [OCRRegion(text: s, boundingBox: .zero, confidence: 1)], languages: ["zh-Hans"])
    }

    private static func blankImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
