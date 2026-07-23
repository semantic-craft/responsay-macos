import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ResponsayCore

/// 070 — Snap & Translate OCR seam: geometry math, result model, provider protocol, and a real
/// end-to-end Apple Vision recognition on a rendered image. Capture (screencapture) and the
/// hotkey live in the macOS app and are device-gated; this exercises the Core that does not need
/// a screen.
struct OCRProviderTests {

    // MARK: - Geometry (pure Y-flip + scale)

    @Test func pixelRect_flipsYAndScales() {
        // A normalized box at the TOP-left of a 200×100 image: Vision origin is bottom-left, so a
        // top band has high maxY. norm = x0..0.5, y 0.8..1.0 → pixel y = (1-1.0)*100 = 0 (top).
        let norm = CGRect(x: 0, y: 0.8, width: 0.5, height: 0.2)
        let px = OCRGeometry.pixelRect(fromNormalized: norm, imageSize: CGSize(width: 200, height: 100))
        #expect(px.minX == 0)
        #expect(px.width == 100)
        #expect(px.height.rounded() == 20)
        #expect(px.minY.rounded() == 0)   // top of the image
    }

    @Test func pixelRect_bottomBandMapsToBottom() {
        // norm y 0..0.2 (bottom in Vision space) → pixel y near image bottom (height-ish).
        let norm = CGRect(x: 0.25, y: 0.0, width: 0.5, height: 0.2)
        let px = OCRGeometry.pixelRect(fromNormalized: norm, imageSize: CGSize(width: 200, height: 100))
        #expect(px.minX == 50)
        #expect(px.minY.rounded() == 80)   // (1 - 0.2) * 100
    }

    // MARK: - OCRResult model

    @Test func result_joinsRegionTextInOrder() {
        let regions = [
            OCRRegion(text: "第一行", boundingBox: .zero, confidence: 0.9),
            OCRRegion(text: "second line", boundingBox: .zero, confidence: 0.8),
        ]
        let result = OCRResult(regions: regions, languages: ["zh-Hans", "en-US"])
        #expect(result.text == "第一行\nsecond line")
        #expect(result.isEmpty == false)
    }

    @Test func result_emptyWhenNoRegions() {
        let result = OCRResult(regions: [], languages: ["en-US"])
        #expect(result.text.isEmpty)
        #expect(result.isEmpty)
    }

    // MARK: - Provider seam (a stub conforms; dispatch returns its result)

    private struct StubOCRProvider: OCRProvider {
        let id = "stub"
        let displayName = "Stub"
        let canned: OCRResult
        func recognize(_ image: CGImage) async throws -> OCRResult { canned }
    }

    @Test func seam_dispatchesThroughProtocol() async throws {
        let canned = OCRResult(
            regions: [OCRRegion(text: "x", boundingBox: .zero, confidence: 1)],
            languages: ["en-US"])
        let provider: any OCRProvider = StubOCRProvider(canned: canned)
        let out = try await provider.recognize(Self.blankImage(width: 4, height: 4))
        #expect(out == canned)
    }

    // MARK: - Apple Vision provider (default)

    @Test func appleVision_identityAndLanguages() {
        let provider = AppleVisionOCRProvider()
        #expect(provider.id == "apple-vision")
        #expect(provider.recognitionLanguages == ["zh-Hans", "en-US"])
    }

    @Test func appleVision_blankImageReturnsEmptyWithoutThrowing() async throws {
        // A blank white image recognizes nothing — the pipeline must return an empty result,
        // not throw. This is the deterministic "wiring is correct" check.
        let result = try await AppleVisionOCRProvider().recognize(Self.blankImage(width: 64, height: 32))
        #expect(result.isEmpty)
        #expect(result.languages == ["zh-Hans", "en-US"])
    }

    @Test func appleVision_recognizesRenderedText() async throws {
        // End-to-end: render big black "HELLO" on white, then OCR it. Vision should read it back.
        let image = Self.textImage("HELLO", width: 320, height: 120)
        let result = try await AppleVisionOCRProvider(recognitionLanguages: ["en-US"]).recognize(image)
        let recognized = result.text.uppercased().filter { !$0.isWhitespace }
        #expect(recognized.contains("HELLO"))
        #expect(result.regions.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
    }

    // MARK: - Image fixtures (CoreText + CoreGraphics, no AppKit → cross-platform test)

    private static func blankImage(width: Int, height: Int) -> CGImage {
        let ctx = context(width: width, height: height)
        return ctx.makeImage()!
    }

    private static func textImage(_ text: String, width: Int, height: Int) -> CGImage {
        let ctx = context(width: width, height: height)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(x: 20, y: 35)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    private static func context(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }
}
