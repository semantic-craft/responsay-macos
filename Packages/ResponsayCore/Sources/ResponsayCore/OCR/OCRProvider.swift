import CoreGraphics
import Foundation

// MARK: - 070 Snap & Translate · OCR provider seam
//
// The seam ADR-0005 asks for: "OCRProvider protocol seam in Core first (Apple Vision default;
// provider seam for vision-LLM / Mistral OCR per blueprint §8)." One method — given a CGImage,
// return recognized text. The on-device Apple Vision provider is the default; a cloud vision-LLM
// provider (issue 074, via the thin backend, dual-run) implements the SAME interface and is
// dispatched against this one. Capture (how we get the CGImage) is the macOS app's job, not the
// provider's — this keeps the seam testable without a screen or a permission grant.

public protocol OCRProvider: Sendable {
    /// Stable engine id, persisted in prefs / used for selection (e.g. `apple-vision`, `cloud`).
    var id: String { get }
    /// Human-facing name shown in settings.
    var displayName: String { get }
    /// Recognize text in one image. On-device providers wrap a synchronous kernel as `async`;
    /// a cloud provider performs an HTTP round-trip. Throws on a hard failure (never returns a
    /// partial/garbage result silently).
    func recognize(_ image: CGImage) async throws -> OCRResult
}

/// Failures shared across providers. Providers may throw their own typed errors too.
/// `LocalizedError` so `localizedDescription` surfaces the real message (not the generic
/// "OCRError error 0") when the controller shows `.failed(message)` to the user.
/// (A `case invalidImage` for image-decode failure will be added when a Data-decoding cloud
/// provider needs it — issue 074 — rather than shipped dead now.)
public enum OCRError: Error, Equatable, LocalizedError {
    /// The recognition request failed at the engine layer (wraps the underlying message).
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .recognitionFailed(message):
            return message
        }
    }
}
