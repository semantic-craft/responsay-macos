import CoreGraphics
import Foundation

// MARK: - 070 Snap & Translate · OCR result model
//
// The structured output of any `OCRProvider`: the recognized text plus per-region
// geometry/confidence. `text` is the raw line-join (provider order, newline-separated);
// smart paragraphing / dual-run replacement (issues 073/074) layer on top of this — they
// do not change the shape. Pure value types (no AppKit), so Core stays iOS/macOS portable
// and the model is unit-testable without a screen.

/// Recognized text for one captured image.
public struct OCRResult: Sendable, Equatable {
    /// Raw per-line join in provider order, newline-separated. Smart paragraphing happens above.
    public let text: String
    /// Per-region text + pixel box + confidence (drives 073's image↔text highlight).
    public let regions: [OCRRegion]
    /// Recognition languages the provider was configured with (e.g. `["zh-Hans", "en-US"]`).
    public let languages: [String]
    /// Whether provider text is backed by boxes, raw rows, or already-flowed prose.
    public let textStructure: OCRTextStructure

    public init(
        text: String,
        regions: [OCRRegion],
        languages: [String],
        textStructure: OCRTextStructure? = nil
    ) {
        self.text = text
        self.regions = regions
        self.languages = languages
        self.textStructure = textStructure ?? (regions.isEmpty ? .flowedText : .regionLines)
    }

    /// Build a result from regions, joining their text in order. Keeps `text` and `regions`
    /// consistent so callers never hand-join.
    public init(regions: [OCRRegion], languages: [String]) {
        self.init(
            text: regions.map(\.text).joined(separator: "\n"),
            regions: regions,
            languages: languages,
            textStructure: .regionLines)
    }

    /// True when nothing was recognized — callers degrade (no Coach hand-off, show guidance).
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 识别到的总字数（去掉所有空白）。面板「N 字」用。
    public var characterCount: Int {
        text.filter { !$0.isWhitespace }.count
    }

    public var supportsSmartParagraphing: Bool {
        switch textStructure {
        case .regionLines: !regions.isEmpty
        case .rawLines: true
        case .flowedText: false
        }
    }

    /// Provider-aware display text: boxes use geometry, raw rows use conservative line joining,
    /// and already-flowed provider text remains unchanged.
    public func displayText(mode: OCRLayoutMode) -> String {
        switch textStructure {
        case .regionLines:
            return regions.isEmpty ? text : OCRParagraphAssembler.text(from: regions, mode: mode)
        case .rawLines:
            return mode == .raw ? text : OCRParagraphAssembler.text(fromRawLines: text)
        case .flowedText:
            return text
        }
    }
}

/// One recognized line/box: text, pixel-space bounding box (origin top-left), confidence 0–1.
public struct OCRRegion: Sendable, Equatable {
    public let text: String
    /// Pixel-space box in the captured image (origin top-left; Y already flipped from Vision).
    public let boundingBox: CGRect
    /// Provider confidence for the top candidate, 0–1 (used by dual-run replacement, issue 074).
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}
