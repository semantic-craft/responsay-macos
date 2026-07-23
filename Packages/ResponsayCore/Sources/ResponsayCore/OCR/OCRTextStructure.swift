/// The shape of text emitted by an OCR provider before Responsay post-processing.
public enum OCRTextStructure: Sendable, Equatable {
    case regionLines
    case rawLines
    case flowedText
}
