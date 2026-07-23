import CoreGraphics
import Foundation
import Testing
@testable import ResponsayCore

// Cloud OCR image encode/decode (ImageIO, cross-platform). Cloud providers upload PNG bytes / data URLs.
struct OCRImageCodecTests {

    private func tinyImage(width: Int = 3, height: Int = 2) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// PNG round-trip: encode then decode back to a CGImage of the same dimensions.
    @Test func pngDataRoundTrips() throws {
        let png = try #require(OCRImageCodec.pngData(from: tinyImage(width: 4, height: 3)))
        #expect(!png.isEmpty)
        let decoded = try #require(OCRImageCodec.cgImage(from: png))
        #expect(decoded.width == 4)
        #expect(decoded.height == 3)
    }

    /// Bad bytes decode to nil rather than crashing.
    @Test func cgImageFromGarbageIsNil() {
        #expect(OCRImageCodec.cgImage(from: Data("not an image".utf8)) == nil)
    }

    /// data: URL carries the mime type and base64 of the bytes.
    @Test func dataURLEncodesBase64() {
        let url = OCRImageCodec.dataURL(from: Data("hi".utf8), mimeType: "image/png")
        #expect(url == "data:image/png;base64,aGk=")
    }
}
