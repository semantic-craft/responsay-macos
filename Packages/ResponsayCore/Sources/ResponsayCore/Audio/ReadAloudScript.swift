import Foundation

/// A pasted document sliced into the units the reader both **speaks** and **highlights**.
///
/// One line = one synthesis request = one exactly-timed highlight span. That equivalence is
/// the whole point: because each line's audio is produced separately, its real duration is
/// known, so the reader never has to guess which sentence is sounding. Sub-line position is
/// interpolated (see `ReadAloudLineTimeline`) — the line itself is ground truth.
///
/// Slicing reuses `TTSTextChunker` (CJK 。！？ + Latin sentence ends, abbreviation- and
/// decimal-safe, soft-splits run-on sentences, merges fragments), run **per paragraph** so the
/// reader can lay the document out with its paragraph breaks intact.
public struct ReadAloudScript: Sendable, Equatable {
    public struct Line: Sendable, Equatable, Identifiable {
        /// Position in the whole document, 0-based — also the highlight index.
        public let id: Int
        /// Owning paragraph, 0-based.
        public let paragraph: Int
        public let text: String

        public init(id: Int, paragraph: Int, text: String) {
            self.id = id
            self.paragraph = paragraph
            self.text = text
        }
    }

    public let lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    /// Slice `text` into speakable lines, keeping paragraph structure.
    public init(
        text: String,
        chunker: TTSTextChunker = TTSTextChunker(),
        policy: TTSChunkingPolicy = .default
    ) {
        var lines: [Line] = []
        // Chunk each paragraph on its own so a paragraph break never lands mid-line, and the
        // paragraph index stays recoverable for layout.
        let paragraphs = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            for chunk in chunker.chunk(paragraph, policy: policy).sorted(by: { $0.order < $1.order }) {
                lines.append(Line(id: lines.count, paragraph: paragraphIndex, text: chunk.text))
            }
        }
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }
    public var count: Int { lines.count }
    public var paragraphCount: Int { (lines.last?.paragraph).map { $0 + 1 } ?? 0 }

    public subscript(index: Int) -> Line? {
        lines.indices.contains(index) ? lines[index] : nil
    }

    /// Lines of one paragraph, in reading order — the unit the reader renders as a `<p>`.
    public func lines(inParagraph paragraph: Int) -> [Line] {
        lines.filter { $0.paragraph == paragraph }
    }

    /// Characters from `index` to the end — drives the "还剩多久" estimate before those
    /// lines have been synthesized (and therefore have no real duration yet).
    public func remainingCharacters(from index: Int) -> Int {
        lines.drop(while: { $0.id < index }).reduce(0) { $0 + $1.text.count }
    }
}
