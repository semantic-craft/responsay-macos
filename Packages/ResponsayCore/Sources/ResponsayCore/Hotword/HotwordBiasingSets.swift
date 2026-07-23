import Foundation

/// The **biasing set** (偏置集): the per-request projection of the `HotwordStore` into the subsets
/// each ASR biasing route draws from — weak-prompt (all) / hard-match (provenance-split).
/// One owner, assembled once, so the routes never drift (the
/// #470/#477/#478/#480 bug class was wiring drift between these). See CONTEXT.md · Biasing set.
public struct HotwordBiasingSets: Sendable, Equatable {
    /// Route 1 — the weak bias hint sent before transcription: all terms, capped at `maxTerms`.
    public let weakPrompt: [String]
    /// Route 2 — the post-ASR hard-match user terms (provenance: typed + auto-learned), eligible
    /// for the #465 confusion-weighted phonetic snap.
    public let hardMatchUser: [String]
    /// Route 2 — the post-ASR hard-match seed terms (generic defaults), exact-only (#470).
    public let hardMatchSeed: [String]
    /// Explicit correction surfaces learned from the edit flywheel: heard surface -> canonical term.
    public let learnedAliases: [String: String]

    public init(
        weakPrompt: [String],
        hardMatchUser: [String],
        hardMatchSeed: [String],
        learnedAliases: [String: String] = [:]
    ) {
        self.weakPrompt = weakPrompt
        self.hardMatchUser = hardMatchUser
        self.hardMatchSeed = hardMatchSeed
        self.learnedAliases = learnedAliases
    }

    /// The single post-ASR hard-match path (ADR-0011): user terms snap near-misses, seeds are
    /// exact-only (#470). The biasing set owns the application, so every transcript consumer
    /// (today `RoutedSpeechCaptureService.stop()`) funnels through one place and can't drift.
    public func enforce(_ transcript: String) -> HotwordEnforcement {
        HotwordHardMatch.enforce(
            transcript,
            userTerms: hardMatchUser,
            seedTerms: hardMatchSeed,
            learnedAliases: learnedAliases)
    }

    /// 517 — the weak prompt with this capture's transient screen terms appended: dictionary
    /// terms first (they survive the cap), transient after, deduped. Weak-prompt lane ONLY —
    /// transient terms never reach hard-match. Empty transient → the exact stored
    /// array, so a disabled 屏幕上下文 keeps requests byte-identical to today.
    public func weakPrompt(augmentedWith transient: [String]) -> [String] {
        guard !transient.isEmpty else { return weakPrompt }
        return HotwordStore.clean(weakPrompt + transient, limit: HotwordStore.maxTerms)
    }

    public func merging(profile: DictationLexicalProfile?) -> HotwordBiasingSets {
        guard let profile else { return self }
        let profileTerms = profile.terms.map(\.text)
        var aliases: [String: String] = [:]
        for alias in profile.aliases where aliases[alias.sourceTerm] == nil {
            aliases[alias.sourceTerm] = alias.term
        }
        aliases.merge(learnedAliases) { _, live in live }
        return HotwordBiasingSets(
            weakPrompt: HotwordStore.clean(weakPrompt + profileTerms, limit: HotwordStore.maxTerms),
            hardMatchUser: HotwordStore.clean(hardMatchUser + profileTerms, limit: HotwordStore.maxTerms),
            hardMatchSeed: hardMatchSeed,
            learnedAliases: aliases)
    }
}

public extension HotwordStore {
    /// The single biasing-set projection (#1 deepening) — replaces the scattered
    /// `ContextHotwordSettings` facade methods that each rebuilt the store and called one
    /// `flattened*` method. Composes the proven building blocks with their caps baked in.
    func biasingSets() -> HotwordBiasingSets {
        let provenance = flattenedByProvenance()
        return HotwordBiasingSets(
            weakPrompt: flattened(),
            hardMatchUser: provenance.user,
            hardMatchSeed: provenance.seed)
    }
}
