import Foundation

/// The opinionated, context-aware actions a text selection can route to
/// (ADR-0022). Redesigned 划词菜单 (Claude Design "Selection Menu"): a resting icon
/// row of instant tools (翻译 / 朗读) expands a labeled smart row centred on the
/// legal-research loop (来源核验 / 来源辅助检索 / 实务辅助 / 任意提问). `ask` (任意提问) is the
/// open-chat escape hatch — it now also absorbs 改写, which was dropped. Only the
/// chosen main transform auto-inserts (ADR-0019); everything else previews / opens
/// a panel / opens authoritative sources.
///
/// `实务辅助` is NOT a `SelectionAction` — it is a dropdown of enabled practice /
/// academic skills, handled in the menu view itself (each pick runs one skill).
public enum SelectionAction: String, Sendable, Equatable, CaseIterable {
    case verify          // 引注源验: 选中 → 自动联网核对法条/案例/文献 → 结果卡（命中跳库核对 / 未命中标「疑似杜撰·待核」/ 卡内可手动挑库）
    case assistedSearch  // 来源辅助检索: 选区 → 可直接粘贴的知网/法宝高级检索式
    case translate       // 翻译 (existing ⌥T) — instant tool, may auto-insert
    case normalizeTypography // 规范排版: 选中 → 确定性整理中文标点/全半角/空格 + AI 拼断行 → 就地替换（不改文字）
    case readAloud       // 朗读 — instant tool, TTS the selection
    case addToDictionary // term-shaped selection → 识别词典 (hotword biasing)
    case ask             // 任意提问: open-chat assistant entry, seeded with the selection

    public var title: String {
        switch self {
        case .verify:          return "引注源验"
        case .assistedSearch:  return "来源辅助检索"
        case .translate:       return "翻译"
        case .normalizeTypography: return "规范排版"
        case .readAloud:       return "朗读"
        case .addToDictionary: return "加入词典"
        case .ask:             return "任意提问"
        }
    }

    public var systemImage: String {
        switch self {
        case .verify:          return "checkmark.seal"
        case .assistedSearch:  return "magnifyingglass"
        case .translate:       return "character.book.closed"
        case .normalizeTypography: return "textformat"
        case .readAloud:       return "speaker.wave.2"
        case .addToDictionary: return "text.book.closed"
        case .ask:             return "bubble.and.pencil"
        }
    }

    /// One-line description shown under the title in the expanded labeled smart rows
    /// (Variant B of the Claude Design 划词菜单). Empty for the instant-row tools
    /// (翻译 / 朗读), which render icon-only and never show a description.
    public var menuDescription: String {
        switch self {
        case .verify:          return "自动联网核对法条 / 案例 / 参考文献 → 命中跳库核对，查不到标「疑似杜撰·待核」"
        case .assistedSearch:  return "选区 → 知网 / 法宝高级检索式，可直接粘贴"
        case .translate:       return ""
        case .normalizeTypography: return "整理中文标点 / 全半角 / 空格与断行，原文一字不改"
        case .readAloud:       return ""
        case .addToDictionary: return "收录为术语 / 个人词条"
        case .ask:             return "开放追问（已吸收改写）"
        }
    }

    /// The in-place transforms that auto-insert their result: `translate` (翻译) and
    /// `normalizeTypography` (规范排版, 就地替换整理后的正文). The rest open a panel / source / session.
    public var autoInserts: Bool { self == .translate || self == .normalizeTypography }
}

public extension SelectionAction {
    /// What controls this action's presence in the 划词菜单. The fixed functions (翻译 / 朗读 /
    /// 加入词典 / 任意提问) are `.always`; the rest appear only once their backing 技能平台 skill
    /// (`.skill`) or 工具 (`.tool`) is 激活. `SelectionMenuGate` evaluates this against the user's
    /// enable-state — the resolver stays purely content-driven and unaware of activation.
    enum Gate: Equatable, Sendable {
        case always
        case skill(id: String)
        case tool(SelectionTool)
    }

    var gate: Gate {
        switch self {
        case .verify:              return .skill(id: "verification.fact_check.cn")
        case .assistedSearch:      return .skill(id: "research.search_strategy.cn")
        case .normalizeTypography: return .tool(.normalizeTypography)
        case .translate, .readAloud, .addToDictionary, .ask: return .always
        }
    }
}
