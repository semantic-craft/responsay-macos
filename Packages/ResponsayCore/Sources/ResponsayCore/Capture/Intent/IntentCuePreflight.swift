import Foundation

/// Deterministic, on-device cue preflight for Intent-aware Dictate (#561, spec decision 22).
///
/// VETO-ONLY: a hit that the verified plan does not explain forces needs-review
/// (`IntentPlanCueCoverage`); a miss authorizes nothing — auto-insert still requires a valid
/// structured plan. That asymmetry shapes the lexicon: false negatives are safe (the compiler
/// still classifies the cue), false positives would drag ordinary prose into review. So the
/// lists are deliberately conservative — ambiguous discourse markers that are routinely genuine
/// content in dictated messages (顺便说一句 / 对了 / "by the way" / bare 不 or "no") are NOT cues,
/// and anything inside paired quotation marks is treated as quoted content, never control speech.
public enum IntentCuePreflight {
    public enum Kind: Sendable, Equatable {
        case correction
        case sideNote
        /// A clue-only unit (口述释字, #562) — detected by the same self-evidencing rule the
        /// extractor uses, so preflight and candidate generation can never disagree.
        case grounding
    }

    /// One flagged source unit. At most one hit per (unit, kind).
    public struct Hit: Sendable, Equatable {
        public let kind: Kind
        public let sourceID: String

        public init(kind: Kind, sourceID: String) {
            self.kind = kind
            self.sourceID = sourceID
        }
    }

    /// Cues that count only when the whole clause IS the cue (after trimming surrounding
    /// whitespace and the trailing separator) — so 「不对称…」 or 「不是所有人…」 never fire.
    private static let clauseExactCorrectionCues: Set<String> = [
        "不对", "不是", "哦不对", "呃不对", "哦不", "错了",
        "no wait", "wait no", "correction"
    ]

    /// Strong self-correction markers, matched anywhere inside a clause (outside quotes).
    private static let anywhereCorrectionCues: [String] = withApostropheVariants([
        "我是说", "我的意思是", "说错了", "口误", "更正一下", "纠正一下",
        "scratch that", "i meant to say", "let me rephrase", "i misspoke"
    ])

    /// Unambiguous "this is for the app, not the recipient" directives about writing.
    private static let anywhereSideNoteCues: [String] = withApostropheVariants([
        "这句不用写", "这句别写", "别写这句", "别写进去", "不用写进去", "不用写出来",
        "这是旁注", "这句是给你的",
        "note to self", "don't write this", "don't write that", "do not write this",
        "don't include this", "don't type this"
    ])

    public static func scan(transcript: String, units: [IntentSourceUnit]) -> [Hit] {
        let quoted = quotedSpans(in: transcript)
        var hits = [Hit]()
        for unit in units {
            if containsCorrectionCue(unit, quoted: quoted) {
                hits.append(Hit(kind: .correction, sourceID: unit.id))
            }
            if containsUnquotedCue(anywhereSideNoteCues, in: unit, quoted: quoted) {
                hits.append(Hit(kind: .sideNote, sourceID: unit.id))
            }
            if IntentSpokenClueExtractor.clueCharacters(in: unit.originalText) != nil,
               !quoted.contains(where: { unit.utf16Range.isWithin($0) }) {
                hits.append(Hit(kind: .grounding, sourceID: unit.id))
            }
        }
        return hits
    }

    // MARK: - Matching

    private static func containsCorrectionCue(
        _ unit: IntentSourceUnit,
        quoted: [IntentSourceRange]
    ) -> Bool {
        if let core = clauseCore(of: unit),
           !intersectsAny(core.range, quoted),
           clauseExactCorrectionCues.contains(core.text.lowercased()) {
            return true
        }
        return containsUnquotedCue(anywhereCorrectionCues, in: unit, quoted: quoted)
    }

    private static func containsUnquotedCue(
        _ cues: [String],
        in unit: IntentSourceUnit,
        quoted: [IntentSourceRange]
    ) -> Bool {
        let text = unit.originalText as NSString
        for cue in cues {
            var search = NSRange(location: 0, length: text.length)
            while search.length > 0 {
                let found = text.range(of: cue, options: [.caseInsensitive], range: search)
                guard found.location != NSNotFound else { break }
                let absolute = IntentSourceRange(
                    location: unit.utf16Range.location + found.location,
                    length: found.length)
                if !intersectsAny(absolute, quoted) { return true }
                let next = found.location + max(found.length, 1)
                search = NSRange(location: next, length: text.length - next)
            }
        }
        return false
    }

    /// The clause text minus leading/trailing whitespace and its trailing separator(s), plus its
    /// absolute UTF-16 range (for the quoted-span check).
    private static func clauseCore(
        of unit: IntentSourceUnit
    ) -> (text: String, range: IntentSourceRange)? {
        let text = unit.originalText
        var start = text.startIndex
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }
        var end = text.endIndex
        while end > start {
            let previous = text.index(before: end)
            let character = text[previous]
            guard character.isWhitespace || IntentSourceSegmenter.separators.contains(character)
            else { break }
            end = previous
        }
        guard start < end else { return nil }
        let core = String(text[start..<end])
        let leadingUTF16 = String(text[text.startIndex..<start]).utf16.count
        return (core, IntentSourceRange(
            location: unit.utf16Range.location + leadingUTF16,
            length: core.utf16.count))
    }

    // MARK: - Quoted spans

    /// UTF-16 spans covered by paired quotation marks (「」 『』 “” and straight double quotes).
    /// An unclosed opener produces no span — its interior stays scannable, the safe direction.
    private static func quotedSpans(in transcript: String) -> [IntentSourceRange] {
        let pairs: [Character: Character] = ["「": "」", "『": "』", "“": "”"]
        var spans = [IntentSourceRange]()
        var openers = [(close: Character, start: Int)]()
        var straightOpen: Int?
        var cursor = 0

        for character in transcript {
            let width = String(character).utf16.count
            defer { cursor += width }
            if let close = pairs[character] {
                openers.append((close, cursor))
            } else if let top = openers.last, character == top.close {
                spans.append(IntentSourceRange(location: top.start, length: cursor + width - top.start))
                openers.removeLast()
            } else if character == "\"" {
                if let start = straightOpen {
                    spans.append(IntentSourceRange(location: start, length: cursor + width - start))
                    straightOpen = nil
                } else {
                    straightOpen = cursor
                }
            }
        }
        return spans
    }

    private static func intersectsAny(
        _ range: IntentSourceRange,
        _ spans: [IntentSourceRange]
    ) -> Bool {
        spans.contains { span in
            range.location < span.location + span.length
                && span.location < range.location + range.length
        }
    }

    /// ASR emits both straight and curly apostrophes — match either spelling.
    private static func withApostropheVariants(_ cues: [String]) -> [String] {
        cues.flatMap { cue -> [String] in
            guard cue.contains("'") else { return [cue] }
            return [cue, cue.replacingOccurrences(of: "'", with: "’")]
        }
    }
}
