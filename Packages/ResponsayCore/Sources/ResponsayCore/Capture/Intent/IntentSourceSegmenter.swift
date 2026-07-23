import Foundation

public enum IntentSourceSegmenter {
    /// Shared clause boundary set — `IntentCuePreflight` trims the same separators so its
    /// clause-exact cue matching aligns with these unit boundaries.
    static let separators: Set<Character> = ["，", "。", "！", "？", "；", ",", ".", "!", "?", ";", "\n"]

    public static func segment(_ transcript: String) -> [IntentSourceUnit] {
        guard !transcript.isEmpty else { return [] }

        var units = [IntentSourceUnit]()
        var unitStart = 0
        var cursor = 0

        for character in transcript {
            cursor += String(character).utf16.count
            guard separators.contains(character) else { continue }
            appendUnit(from: unitStart, to: cursor, transcript: transcript, into: &units)
            unitStart = cursor
        }

        if unitStart < transcript.utf16.count {
            appendUnit(from: unitStart, to: transcript.utf16.count, transcript: transcript, into: &units)
        }
        return units
    }

    private static func appendUnit(
        from start: Int,
        to end: Int,
        transcript: String,
        into units: inout [IntentSourceUnit]
    ) {
        let range = IntentSourceRange(location: start, length: end - start)
        let original = (transcript as NSString).substring(with: range.nsRange)
        units.append(IntentSourceUnit(
            id: String(format: "source-%04d", units.count),
            originalText: original,
            utf16Range: range,
            comparisonKey: comparisonKey(for: original)))
    }

    private static func comparisonKey(for source: String) -> String {
        source
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
