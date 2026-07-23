import Testing
@testable import ResponsayCore

struct WordDiffTests {
    @Test func diff_marksSameDelIns_inOrder() {
        let ops = WordDiff.diff(original: "I very like this", idiomatic: "I really like this")
        #expect(ops == [.same("I"), .del("very"), .ins("really"), .same("like"), .same("this")])
    }

    @Test func diff_handlesPureInsertion() {
        let ops = WordDiff.diff(original: "give me advice", idiomatic: "give me some advice")
        #expect(ops == [.same("give"), .same("me"), .ins("some"), .same("advice")])
    }

    @Test func shouldShow_falseForChineseSource_trueForEnglish() {
        #expect(WordDiff.shouldShow(forSource: "我想说这个") == false)
        #expect(WordDiff.shouldShow(forSource: "I want to say this") == true)
    }
}
