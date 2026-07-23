import AppKit
import XCTest
@testable import ResponsayMac

final class PaddleOCRProviderTests: XCTestCase {
    func testRecognizesRenderedEnglishWhenModelPresent() async throws {
        guard let modelPath = configuredModelPath() else {
            throw XCTSkip("Set PADDLEOCR_TEST_MODEL_DIR to run the real PaddleOCR ONNX smoke test.")
        }
        let modelDir = URL(fileURLWithPath: modelPath, isDirectory: true)
        let provider = try PaddleOCRProvider(modelDir: modelDir)
        let result = try await provider.recognize(try makeImage(text: "Hello OCR"))
        XCTAssertTrue(
            result.text.lowercased().contains("hello"),
            "Expected OCR text to contain Hello, got: \(result.text)")
    }

    private func makeImage(text: String) throws -> CGImage {
        let size = NSSize(width: 720, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(in: NSRect(x: 64, y: 66, width: 600, height: 96), withAttributes: attrs)
        image.unlockFocus()

        var proposed = NSRect(origin: .zero, size: size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw XCTSkip("Could not render test image.")
        }
        return cgImage
    }

    private func configuredModelPath() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let modelPath = env["PADDLEOCR_TEST_MODEL_DIR"], !modelPath.isEmpty {
            return modelPath
        }
        let marker = URL(fileURLWithPath: "/tmp/responsay-paddleocr-model-dir.txt")
        guard let text = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
