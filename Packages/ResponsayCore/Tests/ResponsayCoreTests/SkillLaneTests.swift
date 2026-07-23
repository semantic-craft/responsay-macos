import Testing
@testable import ResponsayCore

/// 技能平台两条 lane 的候选池。听写包的 prompt 是按语音转写写的，出现在写作 lane 上是错配；
/// 声明 lane 让两个池子互斥。缺省（不声明）= 两条都上，导入的第三方包因此零迁移。
@Suite struct SkillLaneTests {

    private func registry() throws -> LegalSkillRegistry { try .loadBundled() }

    private func skill(_ id: String) throws -> LegalSkillCompiled {
        try #require(try registry().skill(id: id))
    }

    // MARK: 内置包的 lane 归属

    @Test func dictationFlavorsAreDictationOnly() throws {
        for id in ["style.clear_structure.cn", "style.formal_expression.cn"] {
            #expect(try skill(id).metadata.lanes == [.dictation])
        }
    }

    @Test func condenseIsWritingOnly() throws {
        #expect(try skill("style.condense.cn").metadata.lanes == [.writing])
    }

    /// 两条 lane 的内置候选池必须互斥——这正是「两边重复」那个问题的根。
    @Test func bundledStylePoolsAreDisjoint() throws {
        let packs = try registry().skills.filter { $0.metadata.kind == .rewrite }
        let dictation = packs.filter { $0.metadata.lanes.contains(.dictation) }.map(\.id)
        let writing = packs.filter { $0.metadata.lanes.contains(.writing) }.map(\.id)
        #expect(!dictation.isEmpty)
        #expect(!writing.isEmpty)
        #expect(Set(dictation).intersection(Set(writing)).isEmpty)
    }

    // MARK: 缺省行为（导入包零迁移）

    @Test func packWithoutLanesAppliesToBoth() throws {
        let md = """
        # 无 lane 声明

        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"style.legacy_import.cn","title":"旧包",
         "domain":"unknown","language":"zh","kind":"rewrite",
         "sceneLayer":{"scene":"unknown","applicableStages":[]}}
        ```

        ## Skill Instructions

        原样保留。
        """
        let compiled = try LegalSkillCompiler().compile(md)
        #expect(compiled.metadata.lanes == SkillLane.allCases)
    }

    /// 空数组等同于未声明——一个哪条 lane 都不出现的包是配置错误，不该让它凭空消失。
    @Test func emptyLanesArrayFallsBackToBoth() throws {
        let md = """
        # 空 lane

        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"style.empty_lanes.cn","title":"空",
         "domain":"unknown","language":"zh","kind":"rewrite","lanes":[],
         "sceneLayer":{"scene":"unknown","applicableStages":[]}}
        ```

        ## Skill Instructions

        原样保留。
        """
        let compiled = try LegalSkillCompiler().compile(md)
        #expect(compiled.metadata.lanes == SkillLane.allCases)
    }

    // MARK: 写作 lane 的默认回落

    /// 写作 lane 里残留的听写包 id（早期 seed 复制过来的）不在写作候选池里，
    /// `ActiveStyleResolver` 查不到就回落到表达升级——无需任何迁移代码。
    @Test func staleDictationIDOnWritingLaneFallsBackToTheDefault() throws {
        let packs = try registry().skills
            .filter { $0.metadata.kind == .rewrite && $0.metadata.lanes.contains(.writing) }
            .map { StylePack.from($0, origin: .builtIn) }
        let active = ActiveStyleResolver.resolve(
            availablePacks: packs,
            activeID: "style.formal_expression.cn",   // 听写包，不在写作池里
            storedToneRaw: nil)
        guard case let .pack(pack) = active.heavyRewriteStyle else {
            Issue.record("写作 lane 应回落到表达升级包"); return
        }
        #expect(pack.id == SkillCategorizer.expressionUpgradeSkillID)
    }
}
