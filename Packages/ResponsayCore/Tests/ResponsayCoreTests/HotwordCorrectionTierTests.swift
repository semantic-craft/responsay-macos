import Testing
@testable import ResponsayCore

/// #500 S3 — the pure pieces of the optional BYOK-LLM correction tier: retrieval gate, prompt
/// shape, and the divergence backstop. The LLM call + macOS wiring are integration (HITL); these
/// pin the logic that decides WHEN to call and WHETHER to trust the reply.
struct HotwordCorrectionTierTests {

    // MARK: Retrieval gate — only fire the LLM when a near-miss actually exists

    @Test func nearMiss_term_phoneticallyClose_butNotPresent_isACandidate() {
        // 拉伦兹 in text, hotword 拉伦茨 — toneless pinyin lalunzi vs lalunci (lev 1), not present.
        let c = HotwordCorrectionCandidates.nearMiss(in: "引用拉伦兹的观点", userTerms: ["拉伦茨"])
        #expect(c == ["拉伦茨"])
    }

    @Test func nearMiss_exactlyPresentTerm_isNotACandidate() {
        let c = HotwordCorrectionCandidates.nearMiss(in: "引用拉伦茨的观点", userTerms: ["拉伦茨"])
        #expect(c.isEmpty)
    }

    @Test func nearMiss_phoneticallyDistantTerm_isNotACandidate() {
        let c = HotwordCorrectionCandidates.nearMiss(in: "今天天气很好", userTerms: ["拉伦茨"])
        #expect(c.isEmpty)
    }

    @Test func nearMiss_emptyInputs_yieldNoCandidates() {
        #expect(HotwordCorrectionCandidates.nearMiss(in: "", userTerms: ["拉伦茨"]).isEmpty)
        #expect(HotwordCorrectionCandidates.nearMiss(in: "引用拉伦兹的观点", userTerms: []).isEmpty)
    }

    @Test func nearMiss_dottedTerm_matchesTheContiguousASRSpan() {
        // 卡尔·拉伦茨 is registered with a middle dot, but ASR emits the contiguous 卡尔拉伦兹. Width
        // must come from syllable count (5), not char count (6), so the span still aligns. (review #1)
        let c = HotwordCorrectionCandidates.nearMiss(in: "引用卡尔拉伦兹的观点", userTerms: ["卡尔·拉伦茨"])
        #expect(c == ["卡尔·拉伦茨"])
    }

    @Test func nearMiss_twoSyllableTerm_doesNotSpuriouslyMatchACrossWordBoundary() {
        // 盘一 (pan-yi) straddles 盘|一 and is 1 pinyin-edit from 判例 (pan-li) — a boundary-free
        // string match would spuriously fire the LLM. Short terms are excluded from retrieval so the
        // "no candidates = no call" guarantee holds on ordinary transcripts. (review #2)
        let c = HotwordCorrectionCandidates.nearMiss(in: "我们来盘一下这个例子", userTerms: ["判例"])
        #expect(c.isEmpty)
    }

    @Test func nearMiss_unrelatedSyllableWindow_isRejected() {
        // A window that is Levenshtein-close but phonetically unrelated (no shared initial/final per
        // syllable) must not be a candidate — retrieval is syllable-aligned, not raw string distance.
        let c = HotwordCorrectionCandidates.nearMiss(in: "请求权基础很重要", userTerms: ["请求权基础"])
        #expect(c.isEmpty)   // exact term present → not a near-miss candidate
    }

    // MARK: Prompt — transcript + only the candidate terms, with the never-paraphrase contract

    @Test func prompt_carriesTranscriptAndCandidatesAndConstraints() {
        let (system, user) = HotwordCorrectionPromptBuilder.build(
            transcript: "引用拉伦兹的观点", candidates: ["拉伦茨", "请求权基础"])
        #expect(user.contains("引用拉伦兹的观点"))
        #expect(user.contains("拉伦茨"))
        #expect(user.contains("请求权基础"))
        // The never-paraphrase / never-insert contract must be present.
        #expect(system.contains("只") && system.contains("别的字一个都不要改"))
        #expect(system.contains("不补标点"))
    }

    // MARK: Divergence guard — candidate-aware: only a near-miss → candidate-term swap may pass

    @Test func guard_acceptsAMinimalTermFix() {
        // 兹→茨: 茨 is a character of candidate 拉伦茨, nothing else changed → accept.
        #expect(HotwordCorrectionGuard.accept(
            original: "引用拉伦兹的观点", corrected: "引用拉伦茨的观点", candidates: ["拉伦茨"]))
    }

    @Test func guard_acceptsANoOpReply() {
        #expect(HotwordCorrectionGuard.accept(
            original: "引用拉伦兹的观点", corrected: "引用拉伦兹的观点", candidates: ["拉伦茨"]))
    }

    @Test func guard_rejectsAWholesaleRewrite() {
        #expect(!HotwordCorrectionGuard.accept(
            original: "引用拉伦兹的观点", corrected: "我认为这个学者的看法非常值得我们深入探讨和借鉴",
            candidates: ["拉伦茨"]))
    }

    @Test func guard_rejectsAnEmptyReply() {
        #expect(!HotwordCorrectionGuard.accept(
            original: "引用拉伦兹的观点", corrected: "   ", candidates: ["拉伦茨"]))
    }

    @Test func guard_rejectsAShortInsertionOfUnspokenWords() {
        // review #3/#4: the fix is right (兹→茨) but the model smuggled in 核心 — those chars belong
        // to no candidate, so a candidate-aware guard rejects even a short insertion the old band passed.
        #expect(!HotwordCorrectionGuard.accept(
            original: "引用拉伦兹的观点", corrected: "引用拉伦茨的核心观点", candidates: ["拉伦茨"]))
    }

    @Test func guard_rejectsADeletionOfSpokenWords() {
        // review #5: the model dropped 李四 (a spoken name, not a candidate) — a length-shrink the
        // old symmetric band waved through. Reject.
        #expect(!HotwordCorrectionGuard.accept(
            original: "请帮我联系张三李四王五", corrected: "请帮我联系张三王五", candidates: ["王五"]))
    }

    @Test func guard_rejectsASameLengthParaphrase() {
        // review #6: 说→讲 is a non-candidate same-length swap the flat lev floor allowed. Reject.
        #expect(!HotwordCorrectionGuard.accept(
            original: "拉伦兹说过这句话", corrected: "拉伦茨讲过这句话", candidates: ["拉伦茨"]))
    }

    @Test func guard_rejectsALongTranscriptAppendedClause() {
        // review #4: on a long transcript the proportional budget used to admit a whole clause; a
        // candidate-aware guard rejects the appended non-candidate content regardless of length.
        let long = "今天我们开会讨论了好几个议题然后又聊到了这位学者的方法论问题"
        #expect(!HotwordCorrectionGuard.accept(
            original: long + "引用拉伦兹",
            corrected: long + "引用拉伦茨这是非常重要的一个理论贡献值得参考",
            candidates: ["拉伦茨"]))
    }

    @Test func guard_resolved_returnsCorrectedWhenSafe_elseOriginal() {
        #expect(HotwordCorrectionGuard.resolved(
            original: "引用拉伦兹", corrected: "引用拉伦茨", candidates: ["拉伦茨"]) == "引用拉伦茨")
        #expect(HotwordCorrectionGuard.resolved(
            original: "引用拉伦兹", corrected: "完全不同的一长串改写内容啊啊啊啊啊", candidates: ["拉伦茨"]) == "引用拉伦兹")
    }

    // MARK: - 516 English (ASCII) near-miss retrieval — 音形骨架分支

    @Test func nearMiss_english_wildMissSpans_areCandidates() {
        // 两个真实听错 fixture(2026-07-03 诊断):meta poll clock(骨架 mtplklk)与
        // Metapocalypse(mtpklips)对 Matt Pocock(mtpk)——hard-match 编辑距离救不回,这层必须召回。
        #expect(HotwordCorrectionCandidates.nearMiss(
            in: "我说一个词叫 meta poll clock", userTerms: ["Matt Pocock"]) == ["Matt Pocock"])
        #expect(HotwordCorrectionCandidates.nearMiss(
            in: "比如我说 Metapocalypse", userTerms: ["Matt Pocock"]) == ["Matt Pocock"])
    }

    @Test func nearMiss_english_exactPresence_isNotACandidate() {
        #expect(HotwordCorrectionCandidates.nearMiss(
            in: "I met Matt Pocock today", userTerms: ["Matt Pocock"]).isEmpty)
    }

    @Test func nearMiss_english_unrelatedProse_hasZeroCandidates() {
        // 零成本不变量:无近音跨度 → 候选空 → 上游 guard !candidates.isEmpty 直接短路,LLM 不被调用。
        #expect(HotwordCorrectionCandidates.nearMiss(
            in: "the weather is nice today", userTerms: ["Matt Pocock"]).isEmpty)
        #expect(HotwordCorrectionCandidates.nearMiss(
            in: "今天天气不错", userTerms: ["Matt Pocock"]).isEmpty)
    }

    @Test func nearMiss_capsAtFiveCandidates() {
        // 6 个词典词同时命中同一跨度 → 只取前 5(原序),防 prompt 膨胀。
        let terms = ["Mat Pok", "Meet Pak", "Mote Pik", "Mite Puk", "Moat Pek", "Mut Pak"]
        let c = HotwordCorrectionCandidates.nearMiss(
            in: "我说一个词叫 meta poll clock", userTerms: terms)
        #expect(c.count == 5)
        #expect(c == Array(terms.prefix(5)))
    }

    // MARK: - 516 guard — 英文 wild-miss 替换放行(候选白名单授权),越权仍回退

    @Test func guard_acceptsEnglishWildMissSwap_despiteShrinkAndDistance() {
        // 替换掉的误识面(15字符)比换入的词条(11)长:净缩 4、编辑距离远超旧 max(4, n/4) 预算——
        // 新引入候选词条的长度就是放宽额度。
        #expect(HotwordCorrectionGuard.accept(
            original: "我说一个词叫 meta poll clock",
            corrected: "我说一个词叫 Matt Pocock",
            candidates: ["Matt Pocock"]))
        #expect(HotwordCorrectionGuard.accept(
            original: "比如我说 Metapocalypse",
            corrected: "比如我说 Matt Pocock",
            candidates: ["Matt Pocock"]))
    }

    @Test func guard_rejectsEnglishEditOutsideCandidates() {
        // 候选替换本身合法,但模型顺手改了别的词(nice→good) → 整体回退。
        #expect(!HotwordCorrectionGuard.accept(
            original: "Metapocalypse is nice",
            corrected: "Matt Pocock is good",
            candidates: ["Matt Pocock"]))
    }

    // MARK: - 516 端到端(检索→mock LLM 回复→guard 终裁)

    @Test func endToEnd_mockReplySnapsToDictionary_orFallsBackOnOverreach() {
        let transcript = "比如我说 Metapocalypse"
        let candidates = HotwordCorrectionCandidates.nearMiss(in: transcript, userTerms: ["Matt Pocock"])
        #expect(candidates == ["Matt Pocock"])
        // LLM 把误识换成词典拼写 → 放行,最终文本含正确拼写。
        #expect(HotwordCorrectionGuard.resolved(
            original: transcript, corrected: "比如我说 Matt Pocock", candidates: candidates)
            == "比如我说 Matt Pocock")
        // LLM 改动候选之外内容(比如→的是) → 回退原文(advisory 红线)。
        #expect(HotwordCorrectionGuard.resolved(
            original: transcript, corrected: "我说的是 Matt Pocock", candidates: candidates)
            == transcript)
    }

    @Test func prompt_tellsModelToUseDictionarySpellingForEnglishTerms() {
        let (system, _) = HotwordCorrectionPromptBuilder.build(
            transcript: "比如我说 Metapocalypse", candidates: ["Matt Pocock"])
        #expect(system.contains("含大小写"))
    }
}
