import Testing
@testable import ResponsayCore

/// 目标七问（academic.goal_brief.cn）— 内置技能的身份与它接的完善剧本。
/// 方法源自 Khazix 的开源 Leader.skill；这里钉的是接线与硬性红线，不是文案。
@Suite struct GoalBriefSkillTests {

    private func registry() throws -> LegalSkillRegistry { try .loadBundled() }

    @Test func skillIsBundledAndNamed() throws {
        let skill = try #require(try registry().skill(id: "academic.goal_brief.cn"))
        #expect(skill.metadata.title == "目标七问")
        #expect(skill.metadata.kind == .generation)
    }

    /// 卡片优先：技能本身不声明 conversation，多轮完善从结果面板进入。
    @Test func skillStaysOneShotSoTheCardComesFirst() throws {
        let skill = try #require(try registry().skill(id: "academic.goal_brief.cn"))
        #expect(skill.metadata.interaction == .oneShot)
    }

    /// 复用既有卡片类型，不新增渲染路径：任务书全文走 insertableParagraph，拍板 + 缺口走
    /// strategyRecommendation。
    @Test func skillReusesExistingCardTypes() throws {
        let skill = try #require(try registry().skill(id: "academic.goal_brief.cn"))
        #expect(skill.metadata.outputCards.contains(.insertableParagraph))
        #expect(skill.metadata.outputCards.contains(.strategyRecommendation))
        #expect(skill.metadata.outputCards.allSatisfy { LegalOutputCardType.allCases.contains($0) })
    }

    /// 技能的硬红线必须钉在推理内核里：不编造信息填缺口；假设必须标注；任务书必须自足
    /// （全文不许有「来找我」）。
    @Test func kernelForbidsFabricationAndRequiresSelfSufficiency() throws {
        let skill = try #require(try registry().skill(id: "academic.goal_brief.cn"))
        #expect(skill.metadata.reasoningKernel.forbidden.contains { $0.contains("编造") })
        #expect(skill.metadata.reasoningKernel.forbidden.contains { $0.contains("假设，未验证") })
        #expect(skill.metadata.reasoningKernel.forbidden.contains { $0.contains("任务书必须自足") })
    }

    /// 推理内核必须覆盖全部七问，缺一问任务书就有系统性盲区。
    @Test func kernelMapsAllSevenQuestions() throws {
        let skill = try #require(try registry().skill(id: "academic.goal_brief.cn"))
        let mapping = skill.metadata.reasoningKernel.mandatoryMapping.joined()
        for question in ["目的 Why", "完成态 Done", "证据 Proof", "反作弊 Anti",
                         "边界 Bounds", "取舍 Trade", "未知 Unknown", "缺口清单"] {
            #expect(mapping.contains(question), "缺少维度：\(question)")
        }
    }

    // MARK: 技能 → 完善剧本

    @Test func skillMapsToTheGoalRefinementScript() {
        #expect(DebateScript.forSkill(id: "academic.goal_brief.cn") == .goalRefinement)
    }

    /// 补全类剧本的按钮文案是「继续完善」，与提示词优化一致。
    @Test func continueActionTitleIsRefinement() {
        #expect(DebateScript.goalRefinement.continueActionTitle == "继续完善")
    }

    /// 默认启用：新装用户在划词菜单里直接能看到这个技能。
    @Test func skillIsDefaultEnabled() {
        #expect(EnabledLegalSkillStore.defaultEnabledIDs.contains("academic.goal_brief.cn"))
        #expect(EnabledLegalSkillStore.resolve(stored: nil).contains("academic.goal_brief.cn"))
    }
}
