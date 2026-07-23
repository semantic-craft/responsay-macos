import Foundation
import Testing
@testable import ResponsayCore

// #561 — the deterministic cue preflight (spec decision 22). It is a VETO-ONLY scanner: a hit
// that the plan does not explain forces review; a miss authorizes nothing. The lexicon is
// deliberately conservative — false negatives are safe (the compiler still handles the cue),
// false positives would push ordinary prose into review, so ambiguous discourse markers
// (顺便说一句 / by the way / bare 不) are deliberately NOT cues.

private func scan(_ transcript: String) -> [IntentCuePreflight.Hit] {
    IntentCuePreflight.scan(
        transcript: transcript,
        units: IntentSourceSegmenter.segment(transcript))
}

@Test func preflight_flagsClauseExactChineseCorrectionCue() {
    let hits = scan("周三开会，不对，周四开会")
    #expect(hits == [.init(kind: .correction, sourceID: "source-0001")])
}

@Test func preflight_flagsStrongCorrectionCueInsideClause() {
    #expect(scan("周三开会，我是说周四开会")
        == [.init(kind: .correction, sourceID: "source-0001")])
    #expect(scan("发给李老师，说错了，发给刘老师")
        == [.init(kind: .correction, sourceID: "source-0001")])
}

@Test func preflight_flagsEnglishCorrectionCues() {
    #expect(scan("Meeting Wednesday, no wait, Thursday")
        == [.init(kind: .correction, sourceID: "source-0001")])
    #expect(scan("Send it Friday, scratch that, Monday morning")
        == [.init(kind: .correction, sourceID: "source-0001")])
    #expect(scan("Ship v2 on Friday, I meant to say Monday")
        == [.init(kind: .correction, sourceID: "source-0001")])
}

@Test func preflight_flagsMixedLanguageCorrection() {
    #expect(scan("把 deadline 定在 Friday，不对，Thursday")
        == [.init(kind: .correction, sourceID: "source-0001")])
}

@Test func preflight_flagsSideNoteDirectives() {
    #expect(scan("帮我谢谢小王，这句不用写，他帮了大忙")
        == [.init(kind: .sideNote, sourceID: "source-0001")])
    #expect(scan("语气正式一点，别写这句，合同周五前要")
        == [.init(kind: .sideNote, sourceID: "source-0001")])
    #expect(scan("Thanks for the docs, don't write this, remind me to review them")
        == [.init(kind: .sideNote, sourceID: "source-0001")])
}

@Test func preflight_ordinaryProse_hasZeroHits() {
    // 「不对」「不是」 as *prefixes* of ordinary words / clauses must not fire.
    #expect(scan("不对称的结构在建筑里很常见，不是所有人都能接受").isEmpty)
    #expect(scan("这个方案没有什么不对的地方").isEmpty)
    #expect(scan("The quarterly report is ready for review, thanks for waiting").isEmpty)
    #expect(scan("我们改成本控制方案之前先开个会").isEmpty)
}

@Test func preflight_quotedCue_isContentNotControl() {
    // Quoted speech (User Story 15/23): cues inside 引号 correct nothing.
    #expect(scan("他当时说“我是说周四”，后来也没改").isEmpty)
    #expect(scan("She replied \"scratch that plan\" and left").isEmpty)
    #expect(scan("他说「这句不用写」的时候我愣住了").isEmpty)
}

@Test func preflight_multipleAndRepeatedCues_dedupedPerUnitAndKind() {
    let hits = scan("周三交，不对，周五交，这句不用写")
    #expect(hits == [
        .init(kind: .correction, sourceID: "source-0001"),
        .init(kind: .sideNote, sourceID: "source-0003")
    ])
    // Two strong cues in one clause → still one hit for that unit.
    #expect(scan("我是说我的意思是周四")
        == [.init(kind: .correction, sourceID: "source-0000")])
}
