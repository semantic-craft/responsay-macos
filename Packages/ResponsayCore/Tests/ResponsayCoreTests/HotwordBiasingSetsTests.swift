import Testing
@testable import ResponsayCore

/// The **biasing set** (偏置集) seam: `HotwordStore.biasingSets()` is the single owner of the
/// per-request biasing subsets — weak-prompt (all) / hard-match (provenance-split). Each
/// subset must match the proven building block it composes (parity safety-net for the refactor),
/// with the confidence threshold and per-subset caps baked in.
struct HotwordBiasingSetsTests {
    private func fixture() -> HotwordStore {
        HotwordStore(
            userTermEntries: [
                HotwordTerm(text: "庭审笔录", source: .manual),                 // trusted (nil conf)
                HotwordTerm(text: "确认案号", source: .auto, confidence: 0.92),
                HotwordTerm(text: "口误词", source: .auto, confidence: 0.5),
            ],
            seeds: [.legal: ["CLSCI", "SSRN"]])
    }

    @Test func weakPromptSet_isTheFullFlattenedDictionary() {
        // Route 1 (weak bias hint): all terms, ≤40 — the existing flattened() dictionary.
        let store = fixture()
        #expect(store.biasingSets().weakPrompt == store.flattened())
    }

    @Test func hardMatchSets_areTheProvenanceSplit() {
        // Route 2 (post-ASR hard-match): user terms (fuzzy-eligible) vs seeds (exact-only).
        let store = fixture()
        let sets = store.biasingSets()
        let split = store.flattenedByProvenance()
        #expect(sets.hardMatchUser == split.user)
        #expect(sets.hardMatchSeed == split.seed)
        #expect(sets.hardMatchUser.contains("庭审笔录"))   // user term → fuzzy-eligible
        #expect(sets.hardMatchSeed.contains("CLSCI"))      // seed → exact-only
    }

    @Test func enforce_isTheOneHardMatchPath_usingTheProvenanceSubsets() {
        // The seam owns the single hard-match path: enforce(transcript) == HotwordHardMatch.enforce
        // with the user/seed split — so stop() and PracticeSpeechRecorder share it instead of
        // duplicating the call.
        let store = HotwordStore(
            userTermEntries: [HotwordTerm(text: "代码仓", source: .manual)], seeds: [:])
        let sets = store.biasingSets()
        let viaSeam = sets.enforce("推到代码厂里")
        let direct = HotwordHardMatch.enforce(
            "推到代码厂里", userTerms: sets.hardMatchUser, seedTerms: sets.hardMatchSeed)
        #expect(viaSeam == direct)
        #expect(viaSeam.text == "推到代码仓里")   // 代码厂→代码仓 (ch/c fuzzy, user-eligible)
    }

    // MARK: - 517 transient screen-term augmentation (weak prompt ONLY)

    @Test func augmentedWeakPrompt_appendsTransientAfterDictionaryAndDedupes() {
        let sets = HotwordBiasingSets(
            weakPrompt: ["庭审笔录", "arXiv"], hardMatchUser: [], hardMatchSeed: [])
        #expect(sets.weakPrompt(augmentedWith: ["Matt Pocock", "arXiv", "Qwen3-ASR"])
            == ["庭审笔录", "arXiv", "Matt Pocock", "Qwen3-ASR"])
    }

    @Test func augmentedWeakPrompt_emptyTransientIsByteIdentical() {
        // 屏幕上下文 OFF（stash 为空）→ 请求与现状字节一致。
        let sets = HotwordBiasingSets(
            weakPrompt: ["庭审笔录", "arXiv"], hardMatchUser: [], hardMatchSeed: [])
        #expect(sets.weakPrompt(augmentedWith: []) == sets.weakPrompt)
    }

    @Test func augmentedWeakPrompt_capKeepsDictionaryFirst() {
        // 截断时词典优先存活：38 词典 + 5 临时 → 40 上限只留 2 个临时词。
        let dictionary = (1...38).map { "词条\($0)" }
        let sets = HotwordBiasingSets(
            weakPrompt: dictionary, hardMatchUser: [], hardMatchSeed: [])
        let merged = sets.weakPrompt(augmentedWith: ["T1", "T2", "T3", "T4", "T5"])
        #expect(merged.count == HotwordStore.maxTerms)
        #expect(Array(merged.prefix(38)) == dictionary)
        #expect(Array(merged.suffix(2)) == ["T1", "T2"])
    }
}
