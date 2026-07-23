import Testing
@testable import ResponsayCore

/// Pins the biasing-list echo guard: a near-empty cloud-ASR capture can return the
/// injected hotword hint verbatim ("CLSCI, SSRN, …") — that must be dropped, while
/// genuine dictation (including a single hotword) must always survive.
@Suite struct HotwordEchoFilterTests {
    let terms = ["CLSCI", "SSRN", "Westlaw", "arXiv", "DOI", "ORCID", "BibTeX", "et al.", "ibid."]

    @Test func verbatimEchoIsDropped() {
        let echo = "CLSCI, SSRN, Westlaw, arXiv, DOI, ORCID, BibTeX, et al., ibid."
        #expect(HotwordEchoFilter.isEcho(echo, terms: terms))
    }

    @Test func partialEchoIsDropped() {
        #expect(HotwordEchoFilter.isEcho("SSRN、Westlaw, arXiv", terms: terms))
    }

    @Test func caseAndSpacingIgnored() {
        #expect(HotwordEchoFilter.isEcho("  ssrn ,  WESTLAW ", terms: terms))
    }

    @Test func singleHotwordSurvives() {
        // A legit one-word dictation of a hotword is NOT a list — keep it.
        #expect(!HotwordEchoFilter.isEcho("arXiv", terms: terms))
    }

    @Test func realProseSurvives() {
        #expect(!HotwordEchoFilter.isEcho("我引用了 CLSCI, 但找不到原文", terms: terms))
    }

    @Test func multiWordTermStaysIntact() {
        // "et al." must not be split on its space into "et" / "al.".
        #expect(HotwordEchoFilter.isEcho("et al., ibid.", terms: terms))
    }

    @Test func trailingPunctuationDriftIsDropped() {
        // Field repro (2026-06-29): the ASR re-punctuates each echoed item, so the
        // dot-terminated seeds "et al." / "ibid." come back as "et al.." / "ibid.."
        // (double dots) and learned terms ride along. Punctuation drift on a single
        // segment must not defeat the all-segments-match test.
        let terms = self.terms + ["理论价值要强调这些方面", "Claude Code", "Zotero", "法墨"]
        let echo = "CLSCI、SSRN、Westlaw、arXiv、DOI、ORCID、BibTeX、et al..、ibid..、理论价值要强调这些方面、Claude Code、Zotero、法墨"
        #expect(HotwordEchoFilter.isEcho(echo, terms: terms))
    }

    @Test func trailingFullStopOnLastSegmentIsDropped() {
        // Model often ends the echoed list with a 。 — that must still count as an echo.
        #expect(HotwordEchoFilter.isEcho("SSRN、Westlaw、arXiv。", terms: terms))
    }

    @Test func emptyInputsAreNotEcho() {
        #expect(!HotwordEchoFilter.isEcho("", terms: terms))
        #expect(!HotwordEchoFilter.isEcho("SSRN, Westlaw", terms: []))
    }

    @Test func transientScreenTermEchoNeedsTheAugmentedList() {
        // 517 — the weak prompt now also carries per-capture screen terms. A near-empty capture
        // can echo THOSE back too, so stop()'s guard must receive the same augmented list the
        // request used: with only the dictionary list this echo would slip through and be inserted.
        let sets = HotwordBiasingSets(
            weakPrompt: ["arXiv"], hardMatchUser: [], hardMatchSeed: [])
        let augmented = sets.weakPrompt(augmentedWith: ["Matt Pocock", "Qwen3-ASR"])
        #expect(HotwordEchoFilter.isEcho("Matt Pocock, Qwen3-ASR", terms: augmented))
        #expect(!HotwordEchoFilter.isEcho("Matt Pocock, Qwen3-ASR", terms: sets.weakPrompt))
    }
}
