import Testing
@testable import ResponsayCore

/// 思路推演（academic.idea_planning.cn）— 内置技能的身份与它接的对抗剧本。
/// 方案结构衍生自 Waza (MIT)，提示词为本项目重写；这里钉的是接线，不是文案。
@Suite struct IdeaPlanningSkillTests {

    private func registry() throws -> LegalSkillRegistry { try .loadBundled() }

    @Test func skillIsBundledAndNamed() throws {
        let skill = try #require(try registry().skill(id: "academic.idea_planning.cn"))
        #expect(skill.metadata.title == "思路推演")
        #expect(skill.metadata.kind == .generation)
    }

    /// 卡片优先：技能本身不声明 conversation，对抗从结果面板进入。
    @Test func skillStaysOneShotSoTheCardComesFirst() throws {
        let skill = try #require(try registry().skill(id: "academic.idea_planning.cn"))
        #expect(skill.metadata.interaction == .oneShot)
    }

    /// 复用既有卡片类型，不新增渲染路径。
    @Test func skillReusesExistingCardTypes() throws {
        let skill = try #require(try registry().skill(id: "academic.idea_planning.cn"))
        #expect(skill.metadata.outputCards.contains(.strategyRecommendation))
        #expect(skill.metadata.outputCards.allSatisfy { LegalOutputCardType.allCases.contains($0) })
    }

    // MARK: 技能 → 对抗剧本

    @Test func adversarialSkillsMapToTheirScripts() {
        #expect(DebateScript.forSkill(id: "academic.idea_planning.cn") == .ideaStressTest)
        #expect(DebateScript.forSkill(id: "academic.counterargument.cn") == .counterargument)
    }

    /// 非对抗技能不得冒出「继续对抗」入口——按钮显隐与剧本选择共用这一个判断。
    @Test func nonAdversarialSkillsHaveNoDebate() {
        #expect(DebateScript.forSkill(id: "verification.fact_check.cn") == nil)
        #expect(DebateScript.forSkill(id: "research.search_strategy.cn") == nil)
        #expect(DebateScript.forSkill(id: "unknown.skill.cn") == nil)
    }

    /// 每个能进对抗的技能都必须真实存在于内置库，否则按钮会指向一个跑不起来的会话。
    @Test func everyDebatableSkillIdIsBundled() throws {
        let reg = try registry()
        for id in ["academic.counterargument.cn", "academic.idea_planning.cn"] {
            #expect(DebateScript.forSkill(id: id) != nil)
            #expect(reg.skill(id: id) != nil)
        }
    }
}
