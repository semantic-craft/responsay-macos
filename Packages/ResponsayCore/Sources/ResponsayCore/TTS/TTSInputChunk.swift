import Foundation

/// One block of text handed to the TTS engine, carrying a stable `segmentID`
/// that downstream timing alignment + word highlight key off (spec §1.2.2/§1.2.5).
public struct TTSInputChunk: Identifiable, Sendable, Equatable, Codable {
    public var segmentID: UUID
    /// Position in the chunked sequence (0-based).
    public var order: Int
    public var text: String

    public var id: UUID { segmentID }

    public init(segmentID: UUID = UUID(), order: Int, text: String) {
        self.segmentID = segmentID
        self.order = order
        self.text = text
    }
}

/// How to slice text into TTS chunks (spec §1.2.5).
public struct TTSChunkingPolicy: Codable, Sendable, Equatable {
    /// Hard ceiling — a chunk is never longer than this.
    public var maxChars: Int
    /// Preferred ceiling — over-long sentences soft-split near here.
    public var softMaxChars: Int
    /// Blocks shorter than this get merged into a neighbour.
    public var minMergeChars: Int
    public var respectParagraphBreaks: Bool
    public var splitOnSentenceBoundary: Bool

    public init(
        maxChars: Int = 220,
        softMaxChars: Int = 160,
        minMergeChars: Int = 24,
        respectParagraphBreaks: Bool = true,
        splitOnSentenceBoundary: Bool = true
    ) {
        self.maxChars = maxChars
        self.softMaxChars = softMaxChars
        self.minMergeChars = minMergeChars
        self.respectParagraphBreaks = respectParagraphBreaks
        self.splitOnSentenceBoundary = splitOnSentenceBoundary
    }

    public static let `default` = TTSChunkingPolicy()
}
