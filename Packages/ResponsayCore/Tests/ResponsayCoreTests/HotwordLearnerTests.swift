import Testing
import Foundation
@testable import ResponsayCore

/// The auto-add judgment (issue 053): promote a corrected term into the hotword
/// store only when it is a small, repeated, term-like fix — never from a large
/// rewrite. Repetition is the safety valve (a one-off "changed my mind" never
/// promotes; a recurring mishearing does). Grounded in RE report §5.3.
@Suite struct HotwordLearnerTests {
    private func chineseTermFix() -> EditDelta {
        EditDelta.compute(inserted: "个人信息处理着，原则", userFinal: "个人信息处理者，原则")
    }

    @Test func termPromotedOnlyAfterRepeat() {
        var learner = HotwordLearner(promotionThreshold: 2)
        #expect(learner.observe(chineseTermFix()).isEmpty)               // 1st time: below threshold
        #expect(learner.observe(chineseTermFix()) ==
                [HotwordCandidate(term: "个人信息处理者", occurrences: 2)]) // 2nd: promoted
        #expect(learner.observe(chineseTermFix()).isEmpty)               // already promoted: no re-emit
    }

    @Test func largeRewriteIsNeverLearned() {
        var learner = HotwordLearner(promotionThreshold: 1)
        let rewrite = EditDelta.compute(
            inserted: "今天讨论数据合规问题", userFinal: "算了换个完全不同的话题说说别的吧")
        #expect(learner.observe(rewrite).isEmpty)
    }

    @Test func loneParticleIsNotTermLike() {
        var learner = HotwordLearner(promotionThreshold: 1)
        // 的 -> 得 : single-char function word, below minTermLength.
        let delta = EditDelta(addedCount: 1, removedCount: 1, isLargeModify: false,
                              substitutions: [WordSubstitution(from: "的", to: "得")])
        #expect(learner.observe(delta).isEmpty)
    }

    @Test func distinctTermsCountIndependently() {
        var learner = HotwordLearner(promotionThreshold: 2)
        let a = EditDelta(addedCount: 1, removedCount: 1, isLargeModify: false,
                          substitutions: [WordSubstitution(from: "处理着", to: "处理者")])
        let b = EditDelta(addedCount: 4, removedCount: 4, isLargeModify: false,
                          substitutions: [WordSubstitution(from: "Quinn three", to: "Qwen3")])
        #expect(learner.observe(a).isEmpty)
        #expect(learner.observe(b).isEmpty)          // each seen once
        #expect(learner.observe(a) == [HotwordCandidate(term: "处理者", occurrences: 2)])
    }
}
