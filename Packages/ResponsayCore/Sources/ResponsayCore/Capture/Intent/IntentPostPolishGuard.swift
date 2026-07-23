import Foundation

/// Stage-2 gate (#564, spec decisions 10/20): the optional Polished renderer's output may reach
/// the field ONLY if these mechanical invariants hold against the already-verified sanitized
/// draft. Any failure falls back to the sanitized draft (never review-less raw, never the
/// polished text) — enhancement is allowed to fail, safety is not. Semantic faithfulness beyond
/// these checks belongs to the corpus gates, not this guard.
enum IntentPostPolishGuard {
    static func accepts(
        polished: String,
        sanitizedDraft: String,
        verified: IntentPlanVerifier.VerifiedPlan
    ) -> Bool {
        // Structured drafts (bullets/steps/paragraphs) are never polished — the deterministic
        // renderer already formatted them, and reflow would break the verified arrangement.
        guard verified.plan.structure == nil else { return false }

        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Canonical entity values are protected literals — must survive verbatim.
        guard verified.selectedCandidates.allSatisfy({ polished.contains($0.value) }) else {
            return false
        }

        // Every digit run of the draft must survive verbatim (numbers, dates, amounts, versions,
        // case numbers). Reformatting (3000 → 3,000) fails closed to the draft.
        guard digitRuns(in: sanitizedDraft).isSubset(of: digitRuns(in: polished)) else {
            return false
        }

        // Control/abandoned speech may not reappear.
        let forbidden = IntentControlFragments.fragments(in: verified)
        guard forbidden.allSatisfy({ !polished.contains($0) }) else { return false }

        // Output language stays the source language (spec: 意图理解永不变成静默翻译).
        guard scriptClass(of: polished) == scriptClass(of: sanitizedDraft) else { return false }

        // Length band: polish tidies, it does not summarize away or invent bulk.
        let draftLength = sanitizedDraft.utf16.count
        let polishedLength = polished.utf16.count
        guard polishedLength <= draftLength * 2 + 20,
              polishedLength * 3 >= draftLength
        else { return false }

        return true
    }

    // MARK: - Mechanical proxies

    private static func digitRuns(in text: String) -> Set<Substring> {
        Set(text.split(whereSeparator: { !$0.isNumber }))
    }

    private enum ScriptClass { case han, latin, mixed, other }

    private static func scriptClass(of text: String) -> ScriptClass {
        var han = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isIdeographic { han += 1 }
            else if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) { latin += 1 }
        }
        let total = han + latin
        guard total > 0 else { return .other }
        let hanRatio = Double(han) / Double(total)
        if hanRatio > 0.7 { return .han }
        if hanRatio < 0.3 { return .latin }
        return .mixed
    }
}
