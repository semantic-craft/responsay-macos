import Foundation

enum IntentPostRenderGuard {
    static func accepts(
        draft: IntentSourceRenderer.Draft,
        finalText: String,
        verified: IntentPlanVerifier.VerifiedPlan
    ) -> Bool {
        let expectedDraft = IntentSourceRenderer.draftText(for: verified)
        let expectedFinal = TextCorrectionRules.apply(to: expectedDraft)
        // Canonical entity values are protected literals (#562): each verified selection must
        // survive the correction rules verbatim, or the result is rejected rather than mangled.
        let entityValuesIntact = verified.selectedCandidates.allSatisfy {
            finalText.contains($0.value)
        }
        return draft.sourceIDs == verified.renderedSourceIDs
            && draft.text == expectedDraft
            && finalText == expectedFinal
            && entityValuesIntact
            && !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
