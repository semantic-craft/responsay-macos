import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Cloud OCR · image encode/decode (cross-platform, ImageIO)
//
// Cloud OCR providers (Mistral / Baidu) upload the captured region as bytes. The on-device
// Apple Vision provider takes a `CGImage` straight, but a cloud round-trip needs PNG bytes →
// base64 (data: URL for Mistral, raw base64 for Baidu's form body). This stays in Core (no
// AppKit/UIKit) via ImageIO so the package stays iOS/macOS portable and the encode is unit-testable.

public enum OCRImageCodec {

    /// `CGImage` → PNG `Data` (nil on encode failure).
    public static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Image bytes (PNG/JPEG/TIFF …) → `CGImage` (nil on bad data).
    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    /// Encoded image bytes → `data:<mime>;base64,<…>` URL string (OpenAI / qwen-vl / Mistral compatible).
    /// Input is **already-encoded** bytes (PNG/JPEG); no bitmap decode here so this stays a pure function.
    public static func dataURL(from imageData: Data, mimeType: String = "image/png") -> String {
        "data:\(mimeType);base64,\(imageData.base64EncodedString())"
    }
}
