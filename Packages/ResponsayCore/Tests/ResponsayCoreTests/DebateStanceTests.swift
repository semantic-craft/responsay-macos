import Testing
@testable import ResponsayCore

/// 多轮对抗剧本驱动。回合位置（`DebateStance`）× 剧本语域（`DebateScript`）→ 注入多轮框的指令。
/// 技能首轮已出结构化卡片，所以对话从加压方接手。纯数据，可测。
@Suite struct DebateStanceTests {

    // MARK: 回合推进（与剧本无关）

    @Test func roundProgressionLoops() {
        #expect(DebateStance.pressure.next == .reply)
        #expect(DebateStance.reply.next == .pressure)
    }

    /// 卡片充当开场，所以第 0 回合直接是加压，不再有单独的开场轮。
    @Test func roundZeroIsPressureBecauseTheCardPlayedTheOpening() {
        #expect(DebateStance.atRound(0) == .pressure)
        #expect(DebateStance.atRound(1) == .reply)
        #expect(DebateStance.atRound(2) == .pressure)
        #expect(DebateStance.atRound(3) == .reply)
    }

    // MARK: 反方观点剧本

    @Test func counterargumentPressureIsTheReviewer() {
        let d = DebateStance.pressure.directive(.counterargument)
        for probe in ["审稿人", "隐含前提", "证据", "反例", "最薄弱"] {
            #expect(d.contains(probe))
        }
    }

    @Test func counterargumentReplyIsTheAuthor() {
        let d = DebateStance.reply.directive(.counterargument)
        for probe in ["作者", "逐条回应", "让步", "检索方向"] {
            #expect(d.contains(probe))
        }
    }

    // MARK: 思路推演剧本

    @Test func ideaStressTestPressureIsTheCriticalReviewer() {
        let d = DebateStance.pressure.directive(.ideaStressTest)
        for probe in ["评审", "可行性", "边界", "更简单的替代", "以后再说"] {
            #expect(d.contains(probe))
        }
    }

    @Test func ideaStressTestReplyIsTheProposer() {
        let d = DebateStance.reply.directive(.ideaStressTest)
        for probe in ["提案人", "逐条回应", "换路径", "具体可判定"] {
            #expect(d.contains(probe))
        }
    }

    // MARK: 提示词优化剧本

    @Test func promptRefinementPressureIsTheCoach() {
        let d = DebateStance.pressure.directive(.promptRefinement)
        for probe in ["提示词教练", "四要素", "缺口", "追问", "不再重复问"] {
            #expect(d.contains(probe))
        }
    }

    @Test func promptRefinementReplyIsTheDrafter() {
        let d = DebateStance.reply.directive(.promptRefinement)
        for probe in ["成稿人", "整合", "完整修订版", "提示词已完备"] {
            #expect(d.contains(probe))
        }
    }

    // MARK: 红线（每一轮都带，且按剧本分）

    @Test func everyDirectiveCarriesItsScriptsRedLine() {
        for stance in DebateStance.allCases {
            #expect(stance.directive(.counterargument).contains("不编造"))       // 文献/引注
            #expect(stance.directive(.counterargument).contains("不下确定结论"))
            #expect(stance.directive(.ideaStressTest).contains("不编造"))        // 事实/数据/来源
            #expect(stance.directive(.ideaStressTest).contains("不下确定结论"))
            #expect(stance.directive(.promptRefinement).contains("不编造"))      // 背景/事实/约束
            #expect(stance.directive(.promptRefinement).contains("复述内部推理"))
        }
    }

    /// 三套剧本不能串台：同一回合位置在不同剧本下给出不同语域的指令。
    @Test func scriptsDoNotBleedIntoEachOther() {
        for stance in DebateStance.allCases {
            let directives = DebateScript.allCases.map { stance.directive($0) }
            #expect(Set(directives).count == directives.count)
        }
        #expect(!DebateStance.pressure.directive(.ideaStressTest).contains("审稿人"))
        #expect(!DebateStance.pressure.directive(.counterargument).contains("评审"))
        #expect(!DebateStance.pressure.directive(.promptRefinement).contains("审稿人"))
        #expect(!DebateStance.pressure.directive(.counterargument).contains("提示词教练"))
    }
}
