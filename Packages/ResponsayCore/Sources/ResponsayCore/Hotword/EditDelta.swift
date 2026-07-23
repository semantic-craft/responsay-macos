import Foundation

/// One word-region replacement the user made (`from` text → `to` text). The
/// hotword flywheel learns the `to` form (issue 053).
public struct WordSubstitution: Sendable, Equatable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The difference between the text Responsay inserted and the text the user left
/// after editing it. Mirrors the Typeless RE report §5.2 tracking fields.
public struct EditDelta: Sendable, Equatable {
    /// Characters present in the final text but not the inserted text.
    public let addedCount: Int
    /// Characters present in the inserted text but not the final text.
    public let removedCount: Int
    /// The user reworked the text rather than fixing a term — a transcription-
    /// quality signal, not something the hotword flywheel should learn from.
    public let isLargeModify: Bool
    /// Word-region replacements (both sides non-empty) the flywheel can learn from.
    public let substitutions: [WordSubstitution]

    /// Fraction of the inserted text (case-insensitive) still present in the final
    /// text. A real in-place correction keeps most of what we inserted; when this is
    /// low the inserted text has vanished — the field was submitted / cleared /
    /// navigated, or we're re-reading a TUI's own chrome (e.g. a terminal after Enter)
    /// — which is not a correction worth learning.
    public let insertedRetainedRatio: Double

    public init(
        addedCount: Int,
        removedCount: Int,
        isLargeModify: Bool,
        substitutions: [WordSubstitution],
        insertedRetainedRatio: Double = 1.0
    ) {
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.isLargeModify = isLargeModify
        self.substitutions = substitutions
        self.insertedRetainedRatio = insertedRetainedRatio
    }

    /// - Parameters:
    ///   - largeModifyRatio: changed chars over this fraction of the inserted
    ///     length count as a large modify.
    ///   - largeModifyFloor: …but never flag tiny absolute edits as large.
    public static func compute(
        inserted: String,
        userFinal: String,
        largeModifyRatio: Double = 0.4,
        largeModifyFloor: Int = 8
    ) -> EditDelta {
        let insertedChars = Array(inserted)
        let finalChars = Array(userFinal)
        let commonChars = lcsLength(insertedChars, finalChars)
        let removed = insertedChars.count - commonChars
        let added = finalChars.count - commonChars

        // ASR often emits English spans in ALL CAPS. A user normalising casing while
        // fixing a nearby proper noun is still a small correction, not a rewrite.
        let largeModifyInsertedChars = Array(inserted.lowercased())
        let largeModifyFinalChars = Array(userFinal.lowercased())
        let largeModifyCommonChars = lcsLength(largeModifyInsertedChars, largeModifyFinalChars)
        let largeModifyRemoved = largeModifyInsertedChars.count - largeModifyCommonChars
        let largeModifyAdded = largeModifyFinalChars.count - largeModifyCommonChars

        let threshold = max(largeModifyFloor, Int(largeModifyRatio * Double(insertedChars.count)))
        let isLarge = (largeModifyAdded + largeModifyRemoved) > threshold

        let retained = largeModifyInsertedChars.isEmpty
            ? 1.0
            : Double(largeModifyCommonChars) / Double(largeModifyInsertedChars.count)

        let subs = substitutions(inserted: tokenize(inserted), userFinal: tokenize(userFinal))
        return EditDelta(addedCount: added, removedCount: removed, isLargeModify: isLarge,
                         substitutions: subs, insertedRetainedRatio: retained)
    }

    // MARK: - Tokenisation

    /// Maximal runs that are neither whitespace nor sentence punctuation, so legal
    /// runs ("个人信息处理者") and English/mixed terms ("Qwen3-ASR") become single tokens.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if isDelimiter(scalar) {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isDelimiter(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        // Sentence punctuation (ASCII + CJK) that bounds a term; hyphen/dot/apostrophe
        // stay in-token so "Qwen3-ASR" / "et al." survive.
        return "，。、；：！？「」『』（）【】《》…,;:!?\"“”‘’()[]".unicodeScalars.contains(scalar)
    }

    // MARK: - Diff

    /// Token-level diff → for each contiguous changed block with tokens on both
    /// sides, a `from`→`to` substitution.
    private static func substitutions(inserted: [String], userFinal: [String]) -> [WordSubstitution] {
        let ops = diffBlocks(inserted, userFinal)
        var result: [WordSubstitution] = []
        for block in ops where !block.from.isEmpty && !block.to.isEmpty {
            result.append(WordSubstitution(from: block.from.joined(separator: " "),
                                           to: block.to.joined(separator: " ")))
        }
        return result
    }

    private struct Block { var from: [String]; var to: [String] }

    /// Walk the LCS alignment, grouping consecutive non-matching tokens into blocks.
    private static func diffBlocks(_ a: [String], _ b: [String]) -> [Block] {
        let table = lcsTable(a, b)
        var i = 0, j = 0
        var blocks: [Block] = []
        var pending = Block(from: [], to: [])
        func flush() {
            if !pending.from.isEmpty || !pending.to.isEmpty { blocks.append(pending) }
            pending = Block(from: [], to: [])
        }
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                flush()
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                pending.from.append(a[i]); i += 1
            } else {
                pending.to.append(b[j]); j += 1
            }
        }
        while i < a.count { pending.from.append(a[i]); i += 1 }
        while j < b.count { pending.to.append(b[j]); j += 1 }
        flush()
        return blocks
    }

    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(repeating: 0, count: b.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            var curr = Array(repeating: 0, count: b.count + 1)
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                curr[j] = a[i] == b[j] ? prev[j + 1] + 1 : max(prev[j], curr[j + 1])
            }
            prev = curr
        }
        return prev[0]
    }
}
