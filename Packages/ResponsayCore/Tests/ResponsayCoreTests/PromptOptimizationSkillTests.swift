import Testing
@testable import ResponsayCore

/// 提示词优化（academic.prompt_optimization.cn）— 内置技能的身份与它接的完善剧本。
/// 优化准则取自 Claude Fable 5 官方提示词指南；这里钉的是接线与硬性红线，不是文案。
@Suite struct PromptOptimizationSkillTests {

    private func registry() throws -> LegalSkillRegistry { try .loadBundled() }

    @Test func skillIsBundledAndNamed() throws {
        let skill = try #require(try registry().skill(id: "academic.prompt_optimization.cn"))
        #expect(skill.metadata.title == "提示词优化")
        #expect(skill.metadata.kind == .generation)
    }

    /// 卡片优先：技能本身不声明 conversation，多轮完善从结果面板进入。
    @Test func skillStaysOneShotSoTheCardComesFirst() throws {
        let skill = try #require(try registry().skill(id: "academic.prompt_optimization.cn"))
        #expect(skill.metadata.interaction == .oneShot)
    }

    /// 复用既有卡片类型，不新增渲染路径：优化稿走 insertableParagraph，改动说明 + 缺口走
    /// strategyRecommendation。
    @Test func skillReusesExistingCardTypes() throws {
        let skill = try #require(try registry().skill(id: "academic.prompt_optimization.cn"))
        #expect(skill.metadata.outputCards.contains(.insertableParagraph))
        #expect(skill.metadata.outputCards.contains(.strategyRecommendation))
        #expect(skill.metadata.outputCards.allSatisfy { LegalOutputCardType.allCases.contains($0) })
    }

    /// 技能的两条硬红线必须钉在推理内核里：不编造信息填缺口；不写「复述内部推理」类指令
    /// （Fable 5 会因此拒答）。
    @Test func kernelForbidsFabricationAndReasoningEcho() throws {
        let skill = try #require(try registry().skill(id: "academic.prompt_optimization.cn"))
        #expect(skill.metadata.reasoningKernel.forbidden.contains { $0.contains("编造") })
        #expect(skill.metadata.reasoningKernel.forbidden.contains { $0.contains("复述或展示内部推理") })
    }

    // MARK: 技能 → 完善剧本

    @Test func skillMapsToThePromptRefinementScript() {
        #expect(DebateScript.forSkill(id: "academic.prompt_optimization.cn") == .promptRefinement)
    }

    /// 结果卡按钮文案跟剧本走：补全类是「继续完善」，对抗类保持「继续对抗」。
    @Test func continueActionTitleFollowsTheScript() {
        #expect(DebateScript.promptRefinement.continueActionTitle == "继续完善")
        #expect(DebateScript.counterargument.continueActionTitle == "继续对抗")
        #expect(DebateScript.ideaStressTest.continueActionTitle == "继续对抗")
    }

    /// 每个能进多轮的技能都必须真实存在于内置库，否则按钮会指向一个跑不起来的会话。
    @Test func everyDebatableSkillIdIsBundled() throws {
        let reg = try registry()
        for id in ["academic.counterargument.cn", "academic.idea_planning.cn",
                   "academic.prompt_optimization.cn"] {
            #expect(DebateScript.forSkill(id: id) != nil)
            #expect(reg.skill(id: id) != nil)
        }
    }

    /// 默认启用：新装用户在划词菜单里直接能看到这个技能。
    @Test func skillIsDefaultEnabled() {
        #expect(EnabledLegalSkillStore.defaultEnabledIDs.contains("academic.prompt_optimization.cn"))
        #expect(EnabledLegalSkillStore.resolve(stored: nil).contains("academic.prompt_optimization.cn"))
    }
}
