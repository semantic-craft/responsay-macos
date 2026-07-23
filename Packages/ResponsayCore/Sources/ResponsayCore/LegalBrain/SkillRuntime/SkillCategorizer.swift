import Foundation

/// 416 — top-level grouping for 设置›技能库: 日常办公 (general rewrite style packs)
/// vs 法律技能 (the legal generation skills + anything explicitly legal). One pure
/// function so the UI sections and any future routing share the exact split.
public enum SkillCategory: String, Sendable, Equatable, CaseIterable {
    case everydayOffice
    case legal
    /// A bundled rewrite skill that is the FIXED dedicated backing of a 改写力度 档
    /// (表达升级 → 表达升级 skill; 轻度润色 → light_polish skill). It powers a tier directly
    /// and is NOT a user-selectable 日常办公 flavor, so the 技能库 hides it from both sections
    /// (b decision, 2026-06-16).
    case rewriteTierDefault

    public var title: String {
        switch self {
        case .everydayOffice: "日常办公"
        case .legal: "法律技能"
        case .rewriteTierDefault: "改写档内置"
        }
    }
}

public enum SkillCategorizer {
    /// Tags that pin a skill to 法律技能 even when it is a rewrite-kind pack
    /// (e.g. a 法律文书润色 style pack). Matched case-insensitively.
    private static let legalTags: Set<String> = ["法律", "法学", "法务", "legal"]

    /// 表达升级 (expression-upgrade) skill id — the dedicated backing of the 表达升级 改写档.
    public static let expressionUpgradeSkillID = "style.expression_upgrade.cn"
    /// 轻度润色 (light-polish) skill id — the dedicated backing of the 轻度润色 改写档.
    public static let lightPolishSkillID = "style.light_polish.cn"

    /// Bundled rewrite skills that back a 改写力度 档 directly (轻度润色 / 表达升级) and are kept OUT
    /// of the 日常办公 selectable list, which is left with the two flavors (清晰结构 / 正式表达).
    static let rewriteTierDefaultIDs: Set<String> = [expressionUpgradeSkillID, lightPolishSkillID]

    public static func category(for skill: LegalSkillCompiled) -> SkillCategory {
        if rewriteTierDefaultIDs.contains(skill.id) { return .rewriteTierDefault }
        return category(kind: skill.metadata.kind, tags: skill.metadata.tags)
    }

    /// 日常办公 = a general rewrite style pack; 法律技能 = a generation skill, or any
    /// skill explicitly tagged legal. Generation skills are always legal (they carry the
    /// reasoning kernel / output cards of the legal platform).
    public static func category(kind: LegalSkillKind, tags: [String]) -> SkillCategory {
        if tags.contains(where: { legalTags.contains($0.lowercased()) }) { return .legal }
        return kind == .rewrite ? .everydayOffice : .legal
    }
}
