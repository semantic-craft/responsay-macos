import Testing
import Foundation
@testable import ResponsayCore

/// 126 — rules-first selection classifier.
/// Verification: mixed zh/en, pure English sentence, pure Chinese, short fragments.
struct SelectionClassifierTests {
    private let classifier = SelectionClassifier()

    @Test func pureEnglishSentence_isPracticeEligible() {
        let c = classifier.classify("I want to know if you can finish this by tomorrow.")
        #expect(c.script == .latin)
        #expect(c.isSentenceShaped)
        #expect(c.isEnglishPracticeEligible)
    }

    @Test func pureChinese_isNotEligible() {
        let c = classifier.classify("你好，世界。这是一个完整的中文句子，用来测试分类器。")
        #expect(c.script == .han)
        #expect(c.isEnglishPracticeEligible == false)
    }

    @Test func shortEnglishFragment_isNotEligible() {
        let c = classifier.classify("Thank you")
        #expect(c.script == .latin)
        #expect(c.isSentenceShaped == false)
        #expect(c.isEnglishPracticeEligible == false)
    }

    @Test func singleWord_isNotEligible() {
        let c = classifier.classify("hello")
        #expect(c.latinWordCount == 1)
        #expect(c.isEnglishPracticeEligible == false)
    }

    @Test func mixedMostlyChinese_isNotEligible() {
        // a few English tokens embedded in Chinese → not predominantly Latin
        let c = classifier.classify("我们今天 review 一下这个 PR 的修改")
        #expect(c.script != .latin)
        #expect(c.isEnglishPracticeEligible == false)
    }

    @Test func mixedMostlyEnglish_isEligible() {
        let c = classifier.classify("Let's go to the meeting room 现在 and start.")
        #expect(c.script == .latin)
        #expect(c.isEnglishPracticeEligible)
    }

    @Test func digitsAndPunctuationOnly_isOther() {
        let c = classifier.classify("123 — 456 !!!")
        #expect(c.script == .other)
        #expect(c.isEnglishPracticeEligible == false)
    }

    @Test func runsSynchronously_returnsValue() {
        // No async surface at all — the call site is straight-line.
        let c = classifier.classify("This should classify immediately.")
        #expect(c.isEnglishPracticeEligible)
    }

    @Test func accentedLatin_countsAsLatin() {
        let c = classifier.classify("Could you résumé the discussion later please?")
        #expect(c.script == .latin)
        #expect(c.isEnglishPracticeEligible)
    }
}
