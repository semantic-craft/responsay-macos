import Observation

/// Editable OCR text projected from one immutable recognition result.
@Observable
public final class OCRTextDraft {
    public private(set) var result: OCRResult
    public private(set) var mode: OCRLayoutMode
    public private(set) var revision = 0
    public private(set) var recognitionRevision = 0

    private var smartText: String
    private var rawText: String

    public init(result: OCRResult, mode: OCRLayoutMode = .smart) {
        self.result = result
        self.mode = mode
        smartText = result.displayText(mode: .smart)
        rawText = result.displayText(mode: .raw)
    }

    public var text: String {
        get { text(for: mode) }
        set { setText(newValue, for: mode) }
    }

    public var characterCount: Int {
        text.filter { !$0.isWhitespace }.count
    }

    public var supportsSmartParagraphing: Bool {
        result.supportsSmartParagraphing
    }

    public func select(_ newMode: OCRLayoutMode) {
        guard newMode != mode else { return }
        mode = newMode
        revision += 1
    }

    public func text(for targetMode: OCRLayoutMode) -> String {
        targetMode == .smart ? smartText : rawText
    }

    public func setText(_ newValue: String, for targetMode: OCRLayoutMode) {
        guard newValue != text(for: targetMode) else { return }
        if targetMode == .smart { smartText = newValue } else { rawText = newValue }
        revision += 1
    }

    public func apply(_ action: OCRTextCleanupAction) {
        text = action.apply(to: text)
    }

    public func restore() {
        text = result.displayText(mode: mode)
    }

    public func replaceResult(_ newResult: OCRResult) {
        result = newResult
        smartText = newResult.displayText(mode: .smart)
        rawText = newResult.displayText(mode: .raw)
        recognitionRevision += 1
        revision += 1
    }
}
