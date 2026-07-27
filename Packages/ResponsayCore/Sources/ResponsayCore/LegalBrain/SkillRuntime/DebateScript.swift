import Foundation

/// Which pair of personas drives a 多轮对抗 session. The loop shape is identical for all
/// (加压方 ↔ 应答方, see `DebateStance`); the script only decides the 语域 and the red line.
/// Picked by whichever skill opened the 对抗, so a new adversarial skill adds a case here
/// rather than a second state machine.
public enum DebateScript: String, Sendable, Equatable, CaseIterable {
    /// 反方观点：审稿人加压 ↔ 作者回应。
    case counterargument
    /// 思路推演：评审压力测试 ↔ 提案人修订。
    case ideaStressTest
    /// 提示词优化：教练追问缺口 ↔ 成稿人整合修订。
    case promptRefinement
    /// 目标七问：任务书教练追问缺口 ↔ 成稿人整合修订（补全形态同 promptRefinement，对照的是七问）。
    case goalRefinement

    /// The 对抗 a skill's result card can hand off to, or `nil` when that skill has none.
    /// Single source of truth for both the continue affordance (shown iff non-nil) and which
    /// script the session then runs, so the button and the personas can't drift apart.
    public static func forSkill(id: String) -> DebateScript? {
        switch id {
        case "academic.counterargument.cn":     return .counterargument
        case "academic.idea_planning.cn":       return .ideaStressTest
        case "academic.prompt_optimization.cn": return .promptRefinement
        case "academic.goal_brief.cn":          return .goalRefinement
        default:                                return nil
        }
    }

    /// 结果卡上继续按钮的文案。对抗类剧本沿用「继续对抗」；提示词优化不是对抗，是补全。
    public var continueActionTitle: String {
        switch self {
        case .counterargument, .ideaStressTest:  return "继续对抗"
        case .promptRefinement, .goalRefinement: return "继续完善"
        }
    }

    /// 加压回合的指令。
    var pressureDirective: String {
        switch self {
        case .counterargument:
            return "现在扮演最严苛的审稿人，针对上面的论证提出最有力的质疑：优先攻击隐含前提是否成立、证据能否支撑结论、是否存在更简洁的替代解释或反例，专挑最薄弱处加压，不替作者找台阶。"
        case .ideaStressTest:
            return "现在扮演最挑剔的评审，对上面的方案做压力测试：可行性与代价是否被低估、边界与失败情形有没有想清楚、是否存在更简单的替代路径、哪些地方还停留在「待定 / 以后再说」这类含糊表述。专挑最薄弱处加压，不替提案人找台阶。"
        case .promptRefinement:
            return "现在扮演提示词教练，先把用户刚才补充的信息（如有）整合进上面的提示词，再对照四要素（意图与背景 / 明确请求 / 边界 / 验收标准）挑出当前最影响产出质量的缺口，向用户追问：每轮只问最重要的 1–2 个问题，问得具体、可以直接口头回答；用户已经补充过的信息不再重复问。"
        case .goalRefinement:
            return "现在扮演任务书教练，先把用户刚才补充的信息（如有）整合进上面的任务书，再对照目标七问（目的 / 完成态 / 证据 / 反作弊 / 边界 / 取舍 / 未知）挑出当前最影响执行结果的缺口，向用户追问：每轮只问最重要的 1–2 个问题，优先问会改变任务书写法的取舍与验收指标，能给选项就给选项并附推荐；用户已经补充过的信息不再重复问。"
        }
    }

    /// 应答回合的指令。
    var replyDirective: String {
        switch self {
        case .counterargument:
            return "现在回到作者，针对审稿人上一轮的质疑逐条回应：能守的说明理由、守不住的明确让步并限缩主张，并指出需要补强的论证环节与文献检索方向。"
        case .ideaStressTest:
            return "现在回到提案人，针对评审上一轮的质疑逐条回应：能守的说明理由、守不住的明确收缩范围或换路径，并把被点名的含糊处改写成具体可判定的说法。"
        case .promptRefinement:
            return "现在回到成稿人，把用户到目前为止补充的全部信息整合进提示词，输出完整修订版全文（可直接复制使用），并用一两句话说明本轮改了什么；若仍有关键缺口，点名最重要的一个继续追问；若已完备，明确说「提示词已完备」。"
        case .goalRefinement:
            return "现在回到成稿人，把用户到目前为止补充的全部信息整合进任务书，输出完整修订版全文（可直接复制交给执行 Agent），并用一两句话说明本轮改了什么；被用户推翻的「拍板」要同步改正文；若仍有关键缺口，点名最重要的一个继续追问；若已完备，明确说「任务书已完备」。"
        }
    }

    /// 该剧本的共享红线，附在每一轮指令末尾。
    var redLine: String {
        switch self {
        case .counterargument:
            return "（红线：文献与判例只给检索方向，不编造标题、作者、出处或引注；不下确定结论。）"
        case .ideaStressTest:
            return "（红线：不编造事实、数据或来源；不确定就标明未知，不用「待定 / 以后再说」搪塞；不下确定结论。）"
        case .promptRefinement:
            return "（红线：不编造用户没有说过的背景、事实或约束来填缺口；不在提示词里加入要求模型复述内部推理的指令。）"
        case .goalRefinement:
            return "（红线：不编造用户没有说过的目标、指标或环境事实来填缺口；未验证的假设必须标「假设，未验证」；任务书里不得出现「来找我 / 中途再问」类指令。）"
        }
    }
}
