import Foundation

/// Deterministic text → TTS chunk slicing (issue 133, spec §1.2.5):
/// 1. paragraphs first, 2. then sentence boundaries, 3. soft-split over-long
/// sentences, 4. merge over-short blocks, 5. stamp each block with a `segmentID`.
///
/// Abbreviations (`Dr.`, `U.S.`, `etc.`) and decimals (`3.50`) are not mis-split.
public struct TTSTextChunker: Sendable {
    public init() {}

    /// Lowercased abbreviations (sans trailing dot) whose `.` is never a boundary.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "vs", "etc", "e.g", "i.e", "eg", "ie",
        "no", "fig", "st", "jr", "sr", "ph.d", "a.m", "p.m", "u.s", "u.k",
        "approx", "dept", "inc", "ltd", "co", "al",
    ]

    public func chunk(_ text: String, policy: TTSChunkingPolicy = .default) -> [TTSInputChunk] {
        let paragraphs: [String]
        if policy.respectParagraphBreaks {
            paragraphs = text.split(whereSeparator: \.isNewline).map(String.init)
        } else {
            paragraphs = [text.replacingOccurrences(of: "\n", with: " ")]
        }

        var blocks: [String] = []
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let sentences = policy.splitOnSentenceBoundary ? Self.splitSentences(trimmed) : [trimmed]
            var paragraphBlocks: [String] = []
            for sentence in sentences {
                paragraphBlocks.append(contentsOf: Self.softSplit(sentence, policy: policy))
            }
            blocks.append(contentsOf: Self.mergeSmall(paragraphBlocks, policy: policy))
        }

        return blocks.enumerated().map { TTSInputChunk(order: $0.offset, text: $0.element) }
    }

    // MARK: - 2. Sentence boundaries

    static func splitSentences(_ text: String) -> [String] {
        let chars = Array(text)
        let count = chars.count
        var sentences: [String] = []
        var start = 0
        var i = 0
        while i < count {
            let ch = chars[i]
            var isBoundary = false
            if ch == "。" || ch == "！" || ch == "？" || ch == "!" || ch == "?" {
                isBoundary = true
            } else if ch == "." {
                isBoundary = isASCIIDotBoundary(chars, at: i)
            }
            if isBoundary {
                var j = i + 1
                while j < count, isClosing(chars[j]) { j += 1 }
                let piece = String(chars[start..<j]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { sentences.append(piece) }
                start = j
                i = j
                continue
            }
            i += 1
        }
        if start < count {
            let tail = String(chars[start..<count]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { sentences.append(tail) }
        }
        return sentences
    }

    private static func isASCIIDotBoundary(_ chars: [Character], at index: Int) -> Bool {
        let prev: Character? = index > 0 ? chars[index - 1] : nil
        let immediate: Character? = index + 1 < chars.count ? chars[index + 1] : nil
        // Decimal: digit . digit
        if let p = prev, p.isNumber, let n = immediate, n.isNumber { return false }
        // Preceding word (letters + interior dots)
        var k = index - 1
        var word = ""
        while k >= 0, chars[k].isLetter || chars[k] == "." {
            word.insert(chars[k], at: word.startIndex)
            k -= 1
        }
        let normalized = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if abbreviations.contains(normalized) { return false }
        // Single-letter initial (e.g. "U." / "S.")
        if word.filter({ $0 != "." }).count == 1, word.first?.isLetter == true { return false }
        // Next non-space must look like a new sentence start.
        guard let next = nextNonSpace(chars, from: index + 1) else { return true } // end of text
        return next.isUppercase || isCJK(next)
    }

    // MARK: - 3. Soft-split over-long sentences

    static func softSplit(_ sentence: String, policy: TTSChunkingPolicy) -> [String] {
        guard sentence.count > policy.softMaxChars else { return [sentence] }
        let chars = Array(sentence)
        var result: [String] = []
        var start = 0
        while chars.count - start > policy.softMaxChars {
            let softLimit = min(start + policy.softMaxChars, chars.count)
            var cut = -1
            var p = softLimit - 1
            while p > start {
                if isSecondaryBoundary(chars[p]) { cut = p + 1; break }
                p -= 1
            }
            if cut <= start { cut = min(start + policy.maxChars, softLimit) } // no boundary → hard cut
            let piece = String(chars[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            start = cut
        }
        if start < chars.count {
            let tail = String(chars[start..<chars.count]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { result.append(tail) }
        }
        return result
    }

    // MARK: - 4. Merge over-short blocks (within a paragraph)

    static func mergeSmall(_ blocks: [String], policy: TTSChunkingPolicy) -> [String] {
        var result: [String] = []
        for block in blocks {
            if let last = result.last,
               last.count < policy.minMergeChars || block.count < policy.minMergeChars,
               last.count + 1 + block.count <= policy.maxChars {
                let joiner = needsSpace(between: last, and: block) ? " " : ""
                result[result.count - 1] = last + joiner + block
            } else {
                result.append(block)
            }
        }
        return result
    }

    // MARK: - Character helpers

    private static func isClosing(_ ch: Character) -> Bool {
        "\"'”’)]）】」』".contains(ch)
    }

    private static func isSecondaryBoundary(_ ch: Character) -> Bool {
        "，,；;、 ".contains(ch)
    }

    private static func needsSpace(between left: String, and right: String) -> Bool {
        guard let l = left.last, let r = right.first else { return false }
        return l.isASCII && r.isASCII && !l.isWhitespace
    }

    private static func nextNonSpace(_ chars: [Character], from index: Int) -> Character? {
        var i = index
        while i < chars.count {
            if !chars[i].isWhitespace { return chars[i] }
            i += 1
        }
        return nil
    }

    private static func isCJK(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
        }
    }
}
