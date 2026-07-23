import Testing
@testable import ResponsayCore

/// Ported verbatim from the retired backend `hotword_match.test.mjs` (ADR-0011),
/// so the Swift app-side enforcer keeps the exact behavior the backend smoked
/// (issue 054). Three cycles: shape + core fix, spacing/acronym/CJK/multiword
/// windows, and the conservative edit-distance + false-positive guards.
struct HotwordHardMatchTests {

    // MARK: Cycle A — shape + the core single-token normalized fix

    @Test func emptyHotwords_leaveTranscriptUntouched() {
        let result = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: [])
        #expect(result.text == "I used qwen3asr today")
        #expect(result.replacements.isEmpty)
    }

    @Test func blankText_isANoOp() {
        let result = HotwordHardMatch.enforce("   ", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "   ")
        #expect(result.replacements.isEmpty)
    }

    @Test func normalizedExactNearMiss_isRewrittenToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
        #expect(result.replacements == [.init(from: "qwen3asr", to: "Qwen3-ASR")])
    }

    @Test func alreadyCorrectSpelling_isLeftAlone() {
        let result = HotwordHardMatch.enforce("I used Qwen3-ASR today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
        #expect(result.replacements.isEmpty)
    }

    @Test func enforcement_isIdempotent() {
        let once = HotwordHardMatch.enforce("I used qwen3asr today", hotwords: ["Qwen3-ASR"]).text
        let twice = HotwordHardMatch.enforce(once, hotwords: ["Qwen3-ASR"]).text
        #expect(twice == once)
    }

    // MARK: Cycle B — spacing / hyphen / acronym / CJK / multiword windows

    @Test func spaceSplitTerm_isRejoinedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("I used qwen3 asr today", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "I used Qwen3-ASR today")
    }

    @Test func hyphenCasedVariant_isNormalizedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("ran qwen3-asr again", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "ran Qwen3-ASR again")
    }

    @Test func letterSpelledAcronym_collapsesToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("published in C L S C I last year", hotwords: ["CLSCI"])
        #expect(result.text == "published in CLSCI last year")
    }

    @Test func latinTermInChinese_isCorrectedWithoutTouchingTheChinese() {
        let result = HotwordHardMatch.enforce("我用 qwen3asr 写论文", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "我用 Qwen3-ASR 写论文")
    }

    @Test func twoWordAuthorName_isCasedToHotwordSpelling() {
        let result = HotwordHardMatch.enforce("cited zhang wei in the intro", hotwords: ["Zhang Wei"])
        #expect(result.text == "cited Zhang Wei in the intro")
    }

    @Test func multipleHotwords_areEnforcedInASinglePass() {
        let result = HotwordHardMatch.enforce("zhang wei used qwen3 asr", hotwords: ["Zhang Wei", "Qwen3-ASR"])
        #expect(result.text == "Zhang Wei used Qwen3-ASR")
        #expect(result.replacements.count == 2)
    }

    // MARK: Cycle C — conservative edit-distance + false-positive guards

    @Test func oneCharMisspellingOfALongTerm_isRepaired() {
        let result = HotwordHardMatch.enforce("ran qwem3-asr again", hotwords: ["Qwen3-ASR"])
        #expect(result.text == "ran Qwen3-ASR again")
    }

    @Test func looselySimilarWord_isLeftUntouched() {
        let result = HotwordHardMatch.enforce("I like cotton fabric", hotwords: ["Kotlin"])
        #expect(result.text == "I like cotton fabric")
        #expect(result.replacements.isEmpty)
    }

    @Test func shortHotwords_requireAnExactNormalizedMatch() {
        // "API" must not capture the unrelated phrase "a pie".
        let result = HotwordHardMatch.enforce("I ate a pie", hotwords: ["API"])
        #expect(result.text == "I ate a pie")
        #expect(result.replacements.isEmpty)
    }

    @Test func shortHotword_stillFixesCasingOnAnExactNormalizedHit() {
        let result = HotwordHardMatch.enforce("the api call", hotwords: ["API"])
        #expect(result.text == "the API call")
    }

    @Test func closestHotwordWins_whenSeveralAreSimilar() {
        let result = HotwordHardMatch.enforce("we used llama", hotwords: ["LLaMA", "Gemma"])
        #expect(result.text == "we used LLaMA")
    }

    // MARK: Cycle D — pinyin / phonetic CJK matching (#465)

    @Test func chineseHomophone_isSnappedToHotwordViaPinyin() {
        // 跟目录 and 根目录 share toneless pinyin (gen mu lu) — snap to the hotword.
        let result = HotwordHardMatch.enforce("切到跟目录下面看看", hotwords: ["根目录"])
        #expect(result.text == "切到根目录下面看看")
        #expect(result.replacements == [.init(from: "跟目录", to: "根目录")])
    }

    @Test func chineseNearHomophone_isSnappedWithinPinyinBudget() {
        // 代码厂 (daimachang) ≈ 代码仓 (daimacang): a 1-edit pinyin near-miss.
        let result = HotwordHardMatch.enforce("推到代码厂里", hotwords: ["代码仓"])
        #expect(result.text == "推到代码仓里")
    }

    @Test func singleCharCJKHotword_doesNotSnapAHomophoneChar() {
        // 库 / 苦 are homophones (ku); a 1-char hotword is too ambiguous to phonetically
        // snap — only ≥2-char CJK terms take the pinyin path.
        let result = HotwordHardMatch.enforce("这日子真苦", hotwords: ["库"])
        #expect(result.text == "这日子真苦")
        #expect(result.replacements.isEmpty)
    }

    @Test func unrelatedChinese_isLeftUntouchedByPinyinPass() {
        let result = HotwordHardMatch.enforce("他今天很高兴", hotwords: ["根目录", "代码仓"])
        #expect(result.text == "他今天很高兴")
        #expect(result.replacements.isEmpty)
    }

    @Test func nonConfusablePinyinNearMiss_isNotSnapped() {
        // 排版 (pai ban) vs hotword 白板 (bai ban): b/p is NOT a Mandarin fuzzy-pinyin
        // confusion, so the confusion-weighted matcher must reject it (a real other word) —
        // even though raw pinyin Levenshtein is only 1.
        let result = HotwordHardMatch.enforce("先把排版做好", hotwords: ["白板"])
        #expect(result.text == "先把排版做好")
        #expect(result.replacements.isEmpty)
    }

    @Test func confusableInitialNearMiss_isSnapped() {
        // 租机 (zu ji) vs hotword 主机 (zhu ji): zh/z is a real fuzzy-pinyin confusion, so
        // it should snap — even though the old length-tiered budget (key "zhuji" ≤5 → exact
        // only) missed it. Confusion-weighting improves recall here, not just precision.
        let result = HotwordHardMatch.enforce("重启租机", hotwords: ["主机"])
        #expect(result.text == "重启主机")
    }

    // MARK: Cycle E — provenance gate (#470): user terms keep fuzzy, seeds are exact-only

    @Test func userTerm_keepsConfusionSnap_underProvenanceSignature() {
        // 代码厂 → 代码仓 (ch/c fuzzy): a user-taught term still snaps under the new signature.
        let result = HotwordHardMatch.enforce("推到代码厂里", userTerms: ["代码仓"], seedTerms: [])
        #expect(result.text == "推到代码仓里")
    }

    @Test func seedTerm_doesNotPhoneticallySnapAHomophone() {
        // 书局 (shu ju) and seed 数据 (shu ju) are toneless homophones. A generic seed must
        // NOT eat the unrelated word — seeds are exact-only, never phonetically snapped.
        let result = HotwordHardMatch.enforce("我去书局看看", userTerms: [], seedTerms: ["数据"])
        #expect(result.text == "我去书局看看")
        #expect(result.replacements.isEmpty)
    }

    @Test func seedTerm_doesNotSnapAnASCIINearMiss() {
        // Westlawe → seed Westlaw is a 1-edit Latin near-miss the fuzzy path would snap. A seed
        // is exact-only, so it must be left alone.
        let result = HotwordHardMatch.enforce("查 Westlawe 数据库", userTerms: [], seedTerms: ["Westlaw"])
        #expect(result.text == "查 Westlawe 数据库")
        #expect(result.replacements.isEmpty)
    }

    @Test func seedTerm_stillFixesCasingOnAnExactNormalizedHit() {
        // Exact (case/format) seed matches still snap — that's not "fuzzy", it's normalization.
        let result = HotwordHardMatch.enforce("查 westlaw 数据库", userTerms: [], seedTerms: ["Westlaw"])
        #expect(result.text == "查 Westlaw 数据库")
    }

    @Test func userTerm_stillSnapsAnASCIINearMiss() {
        // Contrast with the seed case: the same near-miss snaps when the term is user-taught.
        let result = HotwordHardMatch.enforce("查 Westlawe 数据库", userTerms: ["Westlaw"], seedTerms: [])
        #expect(result.text == "查 Westlaw 数据库")
    }

    // MARK: Cycle F — Chinese transliteration of an ASCII hotword (#469)

    @Test func chineseTransliteration_ofRegisteredASCIITerm_isRestored() {
        // ASR heard "Token" as the transliteration 脱肯 (tuo ken); restore the ASCII spelling.
        let result = HotwordHardMatch.enforce("我需要一个脱肯来访问", hotwords: ["Token"])
        #expect(result.text == "我需要一个Token来访问")
        #expect(result.replacements == [.init(from: "脱肯", to: "Token")])
    }

    @Test func multiSyllableTransliteration_isRestored() {
        // 思可瑞特 (si ke rui te, 4 syllables) → Secret.
        let result = HotwordHardMatch.enforce("把思可瑞特存到环境变量", hotwords: ["Secret"])
        #expect(result.text == "把Secret存到环境变量")
    }

    @Test func registeredCJKTerm_isNotEatenByATransliterationOfItsPrefix() {
        // #480: 思可瑞特平台 is a registered hotword present verbatim, and 思可瑞特 (Secret's curated
        // reading) is its prefix. The exact whole-term match must protect the span — the shorter
        // 思可瑞特→Secret transliteration must NOT rewrite already-correct text.
        let result = HotwordHardMatch.enforce(
            "登录思可瑞特平台账号", userTerms: ["Secret", "思可瑞特平台"], seedTerms: [])
        #expect(result.text == "登录思可瑞特平台账号")
        #expect(result.replacements.isEmpty)
    }

    @Test func shortEnglishHotwords_areNotCapturedByAChineseWindow() {
        // AC#2: API / SDK have no reading entry, so a plain Chinese sentence is never captured
        // (we never blind-match all ASCII terms against CJK windows).
        let result = HotwordHardMatch.enforce("这个接口设计得很方便", hotwords: ["API", "SDK"])
        #expect(result.text == "这个接口设计得很方便")
        #expect(result.replacements.isEmpty)
    }

    @Test func transliteration_requiresTheASCIITermToBeRegistered() {
        // ADR-0011 anchoring: 脱肯 is only restored when Token is an active hotword.
        let result = HotwordHardMatch.enforce("我需要一个脱肯来访问", hotwords: [])
        #expect(result.text == "我需要一个脱肯来访问")
        #expect(result.replacements.isEmpty)
    }

    @Test func learnedAliasCanReplayWithoutRegisteredTerms() {
        let result = HotwordHardMatch.enforce(
            "I use Cloud Code",
            userTerms: [],
            seedTerms: [],
            learnedAliases: ["Cloud Code": "Claude Code"])

        #expect(result.text == "I use Claude Code")
        #expect(result.replacements == [.init(from: "Cloud Code", to: "Claude Code")])
    }

    @Test func transliteration_doesNotFireForASeedProvenanceTerm() {
        // Consistent with #470: only user-taught ASCII terms get the transliteration pass.
        let result = HotwordHardMatch.enforce("我需要一个脱肯来访问", userTerms: [], seedTerms: ["Token"])
        #expect(result.text == "我需要一个脱肯来访问")
        #expect(result.replacements.isEmpty)
    }

    // MARK: - #477 多音字 guard (cost-0 toneless-homophone snaps are unsafe across polyphones)

    @Test func polyphoneHotword_doesNotCorruptHomographSurface() {
        // 银行 (yín háng) and 银杏 (yín xìng) are NOT homophones, but .toLatin reads 行
        // context-free as "xing" in both, so they flatten to the same toneless pinyin
        // (yin xing). A taught 银行 must not rewrite 银杏 (ginkgo) into 银行 (bank).
        let result = HotwordHardMatch.enforce("院子里有棵银杏树", userTerms: ["银行"], seedTerms: [])
        #expect(result.text == "院子里有棵银杏树")
        #expect(result.replacements.isEmpty)
    }

    @Test func polyphoneInSharedChar_doesNotMisSnap() {
        // 因乐 (yīn lè) vs 音乐 (yīn yuè): the polyphone 乐 is the *shared* char, read
        // context-free as "le" in both → spurious cost-0 equality. Must not snap.
        let result = HotwordHardMatch.enforce("这是因乐的问题", userTerms: ["音乐"], seedTerms: [])
        #expect(result.text == "这是因乐的问题")
        #expect(result.replacements.isEmpty)
    }

    @Test func polyphoneFreeHomophone_stillSnaps() {
        // The guard is surgical: a cost-0 snap with NO polyphone in window or hotword still
        // fires (跟目录 → 根目录; 根/跟/目/录 are all single-reading characters).
        let result = HotwordHardMatch.enforce("切到跟目录下面", userTerms: ["根目录"], seedTerms: [])
        #expect(result.text == "切到根目录下面")
        #expect(result.replacements == [.init(from: "跟目录", to: "根目录")])
    }

    @Test func confusionEdit_stillSnapsEvenWhenTheHotwordHasAPolyphone() {
        // The guard only blocks cost-0; a real 模糊音 edit (in/ing) into a polyphone-bearing
        // hotword still snaps. 心业 [xin,ye] → 行业 [xing,ye] (cost 1, 行 is a polyphone).
        let result = HotwordHardMatch.enforce("这个心业", userTerms: ["行业"], seedTerms: [])
        #expect(result.text == "这个行业")
        #expect(result.replacements == [.init(from: "心业", to: "行业")])
    }
}
