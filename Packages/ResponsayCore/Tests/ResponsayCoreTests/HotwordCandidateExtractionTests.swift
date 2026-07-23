import Testing
import Foundation
@testable import ResponsayCore

@Suite struct HotwordCandidateExtractionTests {
    @Test func localRulesExtractSmallCorrectionCandidate() async throws {
        let context = HotwordCorrectionContext(
            insertedText: "个人信息处理着，原则",
            userFinalText: "个人信息处理者，原则",
            appName: "Notes",
            windowTitle: "论文草稿")

        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(context)

        #expect(candidates == [
            HotwordCandidateProposal(
                term: "个人信息处理者",
                source: .localRules,
                confidence: 0.86,
                reason: "用户把「个人信息处理着」改成「个人信息处理者」",
                sourceTerm: "个人信息处理着",
                appName: "Notes",
                windowTitle: "论文草稿")
        ])
    }

    @Test func localRulesRejectLargeRewrite() async throws {
        let context = HotwordCorrectionContext(
            insertedText: "这个方案可以",
            userFinalText: "这个方案原则上可以，但是需要补充授权依据、退出机制和责任分配。",
            appName: "Pages",
            windowTitle: "论文草稿")

        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(context)

        #expect(candidates.isEmpty)
    }
}
