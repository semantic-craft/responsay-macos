import Foundation

/// Decides what — if anything — may be learned when the user confirms a candidate in the Intent-aware
/// review capsule (#565). Pure and deterministic: it learns ONLY a real grounded-entity confirmation
/// that produced an insertable result, and only when the confirmed canonical differs from the spoken
/// surface. A confirmed candidate whose id is not a grounded entity (e.g. a correction-chain choice),
/// a re-verification that failed (`needsReview` / `safeUnavailable`), or a surface that already equals
/// the canonical all yield `nil` — so auto-adopted unique candidates, model reorders and side notes
/// can never reach the learning ledger. The learning gates (toggle + sensitive context) live in the
/// macOS sink; this only answers "is there anything the confirmation authorizes learning".
public enum IntentConfirmedAliasLearning {
    static func learnable(
        confirmedCandidateID id: String,
        in proposal: IntentReviewProposal,
        outcome: IntentCompilationOutcome
    ) -> IntentConfirmedAlias? {
        // Only a confirmation that actually produced an insertable result is a learning signal.
        guard case .insertable = outcome else { return nil }
        // The confirmable candidate id equals the whitelisted entity candidate id it selects (#562
        // arbiter). No matching entity → not a grounded-entity confirmation → nothing to learn.
        guard let entity = proposal.entityCandidates.first(where: { $0.id == id }) else { return nil }
        let surface = entity.target.exactQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = entity.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty, !canonical.isEmpty, surface != canonical else { return nil }
        return IntentConfirmedAlias(surface: surface, canonical: canonical)
    }

    /// The gate the macOS sink applies before persisting a confirmed alias (#565 acceptance:
    /// 学习关闭 / 敏感场景 具最高优先级). Learning must be enabled AND neither the surface nor the
    /// canonical may look like protected content (URL / email / secret / code) and the active app
    /// must not be a protected one (Terminal / Xcode …). The learning toggle and the active app
    /// come from macOS; the pattern check reuses the shared `LexicalProfilePrivacyGate`.
    public static func shouldPersist(
        _ alias: IntentConfirmedAlias,
        learningEnabled: Bool,
        appName: String?,
        gate: LexicalProfilePrivacyGate = LexicalProfilePrivacyGate()
    ) -> Bool {
        guard learningEnabled else { return false }
        return gate.rejectionReason(texts: [alias.surface, alias.canonical], appName: appName) == nil
    }
}
