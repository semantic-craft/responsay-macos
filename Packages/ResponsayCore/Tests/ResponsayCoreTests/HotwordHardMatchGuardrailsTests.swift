import Testing
@testable import ResponsayCore

/// #500 S2 — 误纠护栏 (false-positive guards) on top of the #465 phonetic snap, ported in spirit
/// from `HaujetZhao/asr-hotword` (MIT): a proximity/common-word blacklist so an aggressive fuzzy
/// snap can't eat a common word, plus the alias surface that makes aggressive matching safe.
struct HotwordHardMatchGuardrailsTests {

    // MARK: 邻近黑名单 — protected common words are never eaten by a fuzzy snap

    @Test func protectedCommonWord_isNotEatenByAFuzzyNameSnap() {
        // 扶贫 (fu pin) fuzzy-matches a user name hotword 傅平 (fu ping; in/ing is a confusable final,
        // cost 1 ≤ budget 1) — so without a guard 扶贫办 → 傅平办. 扶贫 is a protected common word, so
        // the snap is suppressed and the faithful transcript stands.
        let result = HotwordHardMatch.enforce("我们去扶贫办报到", userTerms: ["傅平"], seedTerms: [])
        #expect(result.text == "我们去扶贫办报到")
        #expect(result.replacements.isEmpty)
    }

    @Test func nonProtectedNearMiss_stillSnaps_soTheGuardIsTargetedNotBlunt() {
        // Regression guard: the protected list must not over-suppress. 代码厂 → 代码仓 (ch/c) is not
        // a common word, so the user term still snaps.
        let result = HotwordHardMatch.enforce("推到代码厂里", userTerms: ["代码仓"], seedTerms: [])
        #expect(result.text == "推到代码仓里")
    }

    @Test func protectedWordThatIsItselfTheHotword_stillNormalizes() {
        // If the user literally registers a "protected" word as their hotword, an EXACT occurrence
        // is a no-op (already correct) — the guard only blocks fuzzy snaps OF the common word, it
        // doesn't stop the word from being a hotword.
        let result = HotwordHardMatch.enforce("先看这批数据", userTerms: ["数据"], seedTerms: [])
        #expect(result.text == "先看这批数据")
        #expect(result.replacements.isEmpty)
    }

    // MARK: 别名映射 — curated cross-form aliases for a registered hotword (general, not ASCII-only)

    @Test func curatedAlias_ofRegisteredHotword_isSnappedWhenFuzzyPathWouldMiss() {
        // 拉伦兹 → 拉伦茨 (Larenz): 茨 cí / 兹 zī differ by z↔c, which is NOT a standard Mandarin
        // confusable (only zh/z, ch/c, sh/s are), so the #465 fuzzy pinyin pass can't reach it. The
        // curated alias maps the heard surface to the registered canonical name (ADR-0011 anchored).
        let result = HotwordHardMatch.enforce("引用拉伦兹的观点", userTerms: ["拉伦茨"], seedTerms: [])
        #expect(result.text == "引用拉伦茨的观点")
        #expect(result.replacements == [.init(from: "拉伦兹", to: "拉伦茨")])
    }

    @Test func curatedAlias_doesNotFireForUnregisteredHotword() {
        // Aliases are anchored: with no registered hotword, the heard surface is left untouched.
        let result = HotwordHardMatch.enforce("引用拉伦兹的观点", userTerms: [], seedTerms: [])
        #expect(result.text == "引用拉伦兹的观点")
        #expect(result.replacements.isEmpty)
    }

    @Test func curatedAlias_isExactOnlyForSeeds() {
        // Aliases ride the user-provenance path (like transliterations, #469/#470); a seed-only
        // registration does not pull in its aliases.
        let result = HotwordHardMatch.enforce("引用拉伦兹的观点", userTerms: [], seedTerms: ["拉伦茨"])
        #expect(result.text == "引用拉伦兹的观点")
        #expect(result.replacements.isEmpty)
    }

    @Test func learnedAlias_repairsExplicitCorrectionSurface() {
        let result = HotwordHardMatch.enforce(
            "open zero",
            userTerms: ["Zotero"],
            seedTerms: [],
            learnedAliases: ["zero": "Zotero"])
        #expect(result.text == "open Zotero")
        #expect(result.replacements == [.init(from: "zero", to: "Zotero")])
    }

    @Test func learnedAlias_repairsMixedSurfaceAsAWhole() {
        let result = HotwordHardMatch.enforce(
            "open Zeta 龙",
            userTerms: ["Zotero"],
            seedTerms: [],
            learnedAliases: ["Zeta 龙": "Zotero"])
        #expect(result.text == "open Zotero")
        #expect(result.replacements == [.init(from: "Zeta 龙", to: "Zotero")])
    }
}
