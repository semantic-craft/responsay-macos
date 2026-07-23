import Foundation

/// Produces word-level timings for highlight + seek, walking the fallback ladder
/// (spec §1.2.6): provider word timing → greedy token align → proportional →
/// sentence-level. Source text is the canonical word split; provider tokens may
/// be finer than words (issue 135).
public protocol WordTimingAligner: Sendable {
    func align(text: String, providerTiming: [TimedWord]?, audioDuration: TimeInterval) -> [TimedWord]
}

public struct DefaultWordTimingAligner: WordTimingAligner, Sendable {
    public init() {}

    public func align(text: String, providerTiming: [TimedWord]?, audioDuration: TimeInterval) -> [TimedWord] {
        let words = Self.tokenize(text)
        guard !words.isEmpty else { return [] }

        if let provider = providerTiming, !provider.isEmpty {
            // P0: provider already word-level → trust it. P2: finer tokens → greedy align.
            if provider.count == words.count {
                return provider
            }
            return Self.alignTimings(words: words, tokens: provider)
        }
        // P3: proportional by token length.
        return Self.proportionalTimings(words: words, duration: audioDuration)
    }

    // MARK: - P2 greedy token → word

    /// Merge provider `tokens` (possibly sub-word) onto canonical `words` by
    /// consuming token characters until each word's character budget is met.
    static func alignTimings(words: [String], tokens: [TimedWord]) -> [TimedWord] {
        var result: [TimedWord] = []
        var tokenIndex = 0
        var lastEnd: TimeInterval = tokens.first?.startTime ?? 0
        for word in words {
            let budget = strippedCount(word)
            var consumed = 0
            var start: TimeInterval?
            var end = lastEnd
            while tokenIndex < tokens.count, consumed < budget {
                let token = tokens[tokenIndex]
                if start == nil { start = token.startTime }
                end = token.endTime
                consumed += strippedCount(token.text)
                tokenIndex += 1
            }
            let s = start ?? lastEnd
            result.append(TimedWord(text: word, startTime: s, endTime: end))
            lastEnd = end
        }
        return result
    }

    // MARK: - P3 proportional

    /// Distribute `duration` across words proportional to character length;
    /// contiguous, with the final word snapped to `duration` (no float drift).
    static func proportionalTimings(words: [String], duration: TimeInterval) -> [TimedWord] {
        let weights = words.map { max(1, strippedCount($0)) }
        let total = weights.reduce(0, +)
        guard total > 0, duration > 0 else {
            return words.map { TimedWord(text: $0, startTime: 0, endTime: 0) }
        }
        var result: [TimedWord] = []
        var cursor: TimeInterval = 0
        for (index, word) in words.enumerated() {
            let start = cursor
            let end: TimeInterval
            if index == words.count - 1 {
                end = duration // snap last to total
            } else {
                end = start + duration * Double(weights[index]) / Double(total)
            }
            result.append(TimedWord(text: word, startTime: start, endTime: end))
            cursor = end
        }
        return result
    }

    public func proportionalTimings(text: String, duration: TimeInterval) -> [TimedWord] {
        Self.proportionalTimings(words: Self.tokenize(text), duration: duration)
    }

    // MARK: - P4 sentence-level

    /// One span covering the whole text — used when no word timing is available.
    public func sentenceTiming(text: String, duration: TimeInterval) -> [TimedWord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [TimedWord(text: trimmed, startTime: 0, endTime: duration)]
    }

    // MARK: - Seek

    /// The word index active at `time` (start ≤ time < end; the last word also
    /// claims `time == end`). Powers highlight; for click-to-seek the caller
    /// reads `timings[i].startTime`.
    public static func wordIndex(at time: TimeInterval, in timings: [TimedWord]) -> Int? {
        for (index, word) in timings.enumerated() {
            if time >= word.startTime, time < word.endTime { return index }
            if index == timings.count - 1, time == word.endTime { return index }
        }
        return nil
    }

    // MARK: - Tokenization

    static func tokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(" ") {
            return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return trimmed.map(String.init) // CJK → per character
    }

    private static func strippedCount(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $1 == " " ? $0 : $0 + 1 }
    }
}
