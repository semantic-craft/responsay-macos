import Testing
import Foundation
@testable import ResponsayCore

/// E2E evaluation for the `academic.goal_brief.cn` skill (目标七问).
/// Live eval — **opt-in only**, gated behind `RUN_LIVE_EVALS=1` so a plain `swift test`
/// never hits the network. Run it explicitly:
///   `RUN_LIVE_EVALS=1 DOUBAO_KEY="..." swift test --filter GoalBriefSkillLiveEvalTests`
@Suite("Goal Brief (目标七问) Live Evaluations")
struct GoalBriefSkillLiveEvalTests {

    @Test(
        "Vague dictated requirement becomes a seven-question task brief with gap list",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LIVE_EVALS"] == "1"))
    func evaluateGoalBrief() async throws {
        let apiKey = try #require(
            ProcessInfo.processInfo.environment["DOUBAO_KEY"],
            "RUN_LIVE_EVALS=1 requires DOUBAO_KEY to be set.")

        let endpoint = LLMEndpoint(
            providerId: "doubao",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: "doubao-seed-2-1-turbo-260628",
            apiKey: apiKey,
            thinkingEnabled: false
        )
        let executor = DirectLegalSkillExecutorAPI(endpoint: endpoint)
        let runtime = try LegalSkillRuntime.bundled(executor: executor)
        let validator = LegalOutputValidator()

        let skill = try #require(runtime.registry.skill(id: "academic.goal_brief.cn"))

        // 口述风格的模糊需求:七问里只带了残缺的 Why/Done/Bounds,Proof/Anti/Trade/Unknown 全缺,
        // 好的产出应该整理出任务书并把缺口点出来。
        let payload = LegalContextPayload(
            selectedText: "我想让 agent 帮我把我们网站的搜索功能优化一下,现在用户搜东西经常搜不到想要的,反馈也说慢,最好这周末之前搞定,注意别把现有功能搞坏了。",
            nearbyHeading: nil,
            scene: .academicWriting,
            stage: .argumentDrafting,
            appName: "Evaluation",
            contextScope: .selectedTextOnly
        )
        let profile = LegalPracticeProfile(
            id: "p", role: .practitioner, modelPreference: .cloudFirst, createdAt: "", updatedAt: "")
        let assembler = LegalPromptAssembler()
        let prompt = assembler.assemble(skill: skill, context: payload, profile: profile)
        let request = LegalSkillExecutionRequest(
            skillId: skill.metadata.id,
            systemPrompt: prompt.system,
            userPrompt: prompt.user,
            modelRoute: .cloudAllowed
        )

        let executionResponse = try await executor.executeSkill(request)
        let envelope = LegalOutputValidator.Envelope(
            runId: "eval-goal-brief",
            skillId: skill.metadata.id,
            scene: .academicWriting,
            stage: .argumentDrafting
        )
        let response = await validator.validate(
            rawOutput: executionResponse.output,
            envelope: envelope,
            repair: { brokenOutput in
                let repairPrompt = assembler.repairPrompt(brokenOutput: brokenOutput)
                let repairRequest = LegalSkillExecutionRequest(
                    skillId: skill.metadata.id,
                    systemPrompt: repairPrompt.system,
                    userPrompt: repairPrompt.user,
                    modelRoute: .cloudAllowed
                )
                return try await executor.executeSkill(repairRequest).output
            }
        )

        // 1. 没有掉进纯文本兜底。
        let isFallback = response.cards.contains {
            if case .fallbackText = $0 { return true }
            return false
        }
        #expect(!isFallback, "Output fell back to plain text — model did not produce LEGAL_OUTPUT/v1")

        // 2. 任务书全文覆盖七问的全部小节。
        let brief = response.cards.compactMap { card -> InsertableParagraphCard? in
            if case .insertableParagraph(let v) = card { return v }
            return nil
        }.first
        let briefCard = try #require(brief, "missing insertableParagraph task brief")
        for section in ["目的", "完成态", "证据", "反作弊", "边界", "取舍", "未知"] {
            #expect(briefCard.text.contains(section), "任务书缺少小节:\(section)")
        }

        // 3. strategyRecommendation 卡存在,且点出了缺口(输入刻意缺 Proof/Anti/Trade/Unknown)。
        let strategy = response.cards.compactMap { card -> StrategyRecommendationCard? in
            if case .strategyRecommendation(let v) = card { return v }
            return nil
        }.first
        let strategyCard = try #require(strategy, "missing strategyRecommendation card")
        let gaps = strategyCard.recommendations.filter { $0.strategy.hasPrefix("缺口") }
        #expect(!gaps.isEmpty, "expected at least one 「缺口:」 item for a vague requirement")

        print("=== 一句话目的重述 ===\n\(strategyCard.title)\n")
        print("=== 整理与拍板 ===")
        for item in strategyCard.recommendations {
            print("- \(item.strategy)\n  理由:\(item.rationale)")
        }
        print("\n=== 任务书全文(insertableParagraph, pendingVerification=\(briefCard.containsPendingVerification)) ===\n\(briefCard.text)")
    }
}
