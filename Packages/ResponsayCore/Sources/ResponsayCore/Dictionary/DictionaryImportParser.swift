import Foundation

/// File format for a bulk dictionary import (issue 519).
public enum DictionaryImportFormat: Sendable {
    /// One term per line.
    case txt
    /// One record per line; the term is the first comma-separated column.
    case csv
}

/// The partitioned result of parsing an import file: what would be added, what
/// was skipped as a duplicate, and what failed validation. Counts drive the
/// preview; `additions` is what gets written on confirm.
public struct DictionaryImportPlan: Equatable, Sendable {
    /// New, valid, deduplicated terms in first-seen order — the write list.
    public var additions: [String]
    /// Terms skipped because they already exist (in the dictionary or earlier in the batch).
    public var duplicates: [String]
    /// Non-blank lines rejected by validation (currently: exceeds the length ceiling).
    public var invalid: [String]

    public var addCount: Int { additions.count }
    public var duplicateCount: Int { duplicates.count }
    public var invalidCount: Int { invalid.count }

    public init(additions: [String] = [], duplicates: [String] = [], invalid: [String] = []) {
        self.additions = additions
        self.duplicates = duplicates
        self.invalid = invalid
    }
}

/// Pure parser for bulk dictionary import. Reuses `addManual`'s rules — trim
/// whitespace, drop empties, honor `maxTermLength` — but for a bulk import an
/// over-long line is *rejected and surfaced* rather than silently truncated,
/// so the preview can show it instead of writing a mangled term.
public enum DictionaryImportParser {
    public static func parse(
        _ contents: String,
        format: DictionaryImportFormat,
        existing: [String],
        maxLength: Int = HotwordStore.maxTermLength
    ) -> DictionaryImportPlan {
        var seen = Set(existing)
        var plan = DictionaryImportPlan()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let term = firstField(String(rawLine), format: format)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { continue } // ponytail: blank/whitespace line is formatting, drop silently
            if term.count > maxLength {
                plan.invalid.append(term)
            } else if seen.contains(term) {
                plan.duplicates.append(term)
            } else {
                seen.insert(term)
                plan.additions.append(term)
            }
        }
        return plan
    }

    private static func firstField(_ line: String, format: DictionaryImportFormat) -> String {
        switch format {
        case .txt:
            return line
        case .csv:
            return line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? line
        }
    }
}
