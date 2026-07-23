import Foundation

/// A deterministic 划词 tool that is **not** an LLM skill (so it has no `*.LEGAL_SKILL.md`
/// entry) yet still follows the 技能平台 activation model: it appears in the 划词菜单 only once
/// 激活, exactly like the skill-backed actions. Today the only member is 规范排版
/// (`normalizeTypography`) — the rule-based Chinese typesetting cleanup shipped in 1.5.4.
///
/// Tools are activated in the 技能平台「工具」区 and gate their matching `SelectionAction` via
/// `SelectionAction.gate` → `.tool(_)`. `rawValue` is the persisted id, namespaced `tool.*` so it
/// never collides with a skill id in shared storage / logs.
public enum SelectionTool: String, Sendable, Equatable, CaseIterable, Identifiable {
    case normalizeTypography = "tool.normalize_typography"

    public var id: String { rawValue }

    /// 显示名 — kept identical to `SelectionAction.normalizeTypography.title` so the menu, the
    /// settings 面板 and the 技能平台 card all read the same word.
    public var title: String {
        switch self {
        case .normalizeTypography: return "规范排版"
        }
    }

    /// One-line 技能平台 card description.
    public var summary: String {
        switch self {
        case .normalizeTypography:
            return "确定性整理中文标点 / 全半角 / 空格，再在指纹护栏下让 AI 只重排断行——正文一字不改，就地替换选区。"
        }
    }

    public var systemImage: String {
        switch self {
        case .normalizeTypography: return "textformat"
        }
    }
}
