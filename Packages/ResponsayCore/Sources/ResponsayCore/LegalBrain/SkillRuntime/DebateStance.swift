import Foundation

/// 多轮对抗里当前处在哪一侧。剧本（`DebateScript`）决定语域，这里只决定回合位置，两者相乘
/// 得到注入多轮框的那一句指令。纯数据（类比 `RegisterTier`），可单测。
///
/// 发起对抗的技能首轮已经产出过结构化卡片（反方观点的论证重构 / 思路推演的方案陈述），由卡片
/// 充当开场，所以对话从**加压方**接手 —— `atRound(0) == .pressure`，没有单独的开场轮。
///
/// 前身是 247/489 的 `LitigationStance`（庭前推演蓝图 → 对方代理人抗辩 → 我方反驳）。诉讼策略
/// 技能退场后，对抗能力迁到学术技能，并在思路推演加入时拆出 script 维度。
public enum DebateStance: String, Sendable, Equatable, CaseIterable {
    /// 加压方：审稿人 / 评审。
    case pressure
    /// 应答方：作者 / 提案人。
    case reply

    /// 注入当轮多轮框的指令 —— 剧本的角色指令 + 该剧本的红线。
    public func directive(_ script: DebateScript) -> String {
        switch self {
        case .pressure: return script.pressureDirective + script.redLine
        case .reply:    return script.replyDirective + script.redLine
        }
    }

    /// 对抗剧本的下一回合：加压 ↔ 应答（循环加压）。
    public var next: DebateStance {
        switch self {
        case .pressure: return .reply
        case .reply:    return .pressure
        }
    }

    /// 0-based 回合 → stance。多轮框据用户回合数推算当轮 stance（无可变状态）：
    /// 回合 0 = 加压（结构化卡片已充当开场），之后沿 `next` 循环。
    public static func atRound(_ round: Int) -> DebateStance {
        var stance = DebateStance.pressure
        for _ in 0..<max(0, round) { stance = stance.next }
        return stance
    }
}
