import Foundation

enum IntentSourceRenderer {
    struct Draft: Sendable, Equatable {
        let text: String
        let sourceIDs: [String]
    }

    static func render(_ verified: IntentPlanVerifier.VerifiedPlan) -> Draft {
        Draft(text: draftText(for: verified), sourceIDs: verified.renderedSourceIDs)
    }

    /// The one deterministic composition rule, shared with the post-render guard so both sides
    /// recompute the identical expectation. Each rendered unit gets its verified candidate
    /// values spliced over their app-computed slots; the verified structure (if any) alone
    /// decides paragraphs / bullets / numbered steps (#563). Model text appears nowhere —
    /// values come from the whitelist table, unit text from the frozen transcript.
    static func draftText(for verified: IntentPlanVerifier.VerifiedPlan) -> String {
        let sourceByID = Dictionary(uniqueKeysWithValues: verified.sourceUnits.map { ($0.id, $0) })
        let candidatesByUnit = Dictionary(
            grouping: verified.selectedCandidates, by: { $0.target.sourceID })
        func text(for id: String) -> String? {
            guard let unit = sourceByID[id] else { return nil }
            return spliced(unit: unit, candidates: candidatesByUnit[id] ?? [])
        }

        guard let structure = verified.plan.structure else {
            return verified.renderedSourceIDs.compactMap(text(for:)).joined()
        }
        let groupTexts = structure.groups.map { group in
            group.compactMap(text(for:)).joined()
        }
        switch structure.kind {
        case .paragraphs:
            return groupTexts.map(itemText).joined(separator: "\n\n")
        case .bulletList:
            return groupTexts.map { "- " + itemText($0) }.joined(separator: "\n")
        case .numberedSteps:
            return groupTexts.enumerated()
                .map { "\($0.offset + 1). " + itemText($0.element) }
                .joined(separator: "\n")
        }
    }

    /// Deterministic item cleanup: surrounding whitespace plus a dangling clause comma or
    /// semicolon go; sentence-final punctuation (。！？.) stays. A fixed character rule — not
    /// model rewriting.
    private static func itemText(_ text: String) -> String {
        var item = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = item.last, "，,；;、".contains(last) {
            item = item.dropLast()
        }
        return String(item)
    }

    private static func spliced(
        unit: IntentSourceUnit,
        candidates: [IntentEntityCandidate]
    ) -> String {
        guard !candidates.isEmpty else { return unit.originalText }
        let text = NSMutableString(string: unit.originalText)
        let ordered = candidates.sorted { $0.target.range.location > $1.target.range.location }
        for candidate in ordered {
            let local = NSRange(
                location: candidate.target.range.location - unit.utf16Range.location,
                length: candidate.target.range.length)
            guard local.location >= 0, local.location + local.length <= text.length else { continue }
            text.replaceCharacters(in: local, with: candidate.value)
        }
        return text as String
    }
}
