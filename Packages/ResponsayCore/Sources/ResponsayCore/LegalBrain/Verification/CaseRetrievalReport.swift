import Foundation

/// 246 — 类案检索策略助手（PRD S3）。把"焦点拆解（LLM）+ 分层渠道（#474 `CaseRetrievalPlanner`）"
/// 渲染成可执行的"检索作战图"Markdown：每条 = 检索式 + 直达链接，顶部带安全降级提示。纯渲染、可测；
/// 真正的联网检索 / 判例须经 #473 案号验证 + 来源核验。
public enum CaseRetrievalReport {
    /// 安全降级提示（acceptance：未联网核验前只给检索式、不给判例）。
    public static let safetyNote =
        "⚠️ 以下仅为检索策略（检索式 + 直达链接）。未经真正联网核验，不提供具体判例；任何判例须经案号验证 + 来源核验后方可引用。"

    /// 完整 Core 路径：LLM 拆出的「焦点(标题 + 案情字段)」→ 分层渠道(#474) → 作战图 Markdown。
    public static func build(focuses: [(label: String, facts: CaseFacts)]) -> String {
        markdown(focuses: focuses.map { ($0.label, CaseRetrievalPlanner.plan($0.facts)) })
    }

    /// 渲染单个争议焦点的检索作战图。
    public static func markdown(focus: String, plans: [CaseRetrievalPlan]) -> String {
        [safetyNote, "", section(focus: focus, plans: plans)].joined(separator: "\n")
    }

    /// 多个争议焦点聚合为一份报告：安全提示只在顶部出现一次。
    public static func markdown(focuses: [(focus: String, plans: [CaseRetrievalPlan])]) -> String {
        ([safetyNote] + focuses.map { section(focus: $0.focus, plans: $0.plans) })
            .joined(separator: "\n\n")
    }

    /// 一个焦点的小节（不含安全提示），= 标题 + 每条渠道「检索式 + 直达链接」。
    private static func section(focus: String, plans: [CaseRetrievalPlan]) -> String {
        var lines = ["### \(focus)"]
        for plan in plans {
            if let url = plan.url {
                lines.append("- [\(plan.channel.name)](\(url.absoluteString))：`\(plan.query)`")
            } else {
                lines.append("- \(plan.channel.name)：`\(plan.query)`")
            }
        }
        return lines.joined(separator: "\n")
    }
}
