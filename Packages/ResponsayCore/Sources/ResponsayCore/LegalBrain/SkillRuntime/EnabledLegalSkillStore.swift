import Foundation

// MARK: - 220 EnabledLegalSkillStore
//
// Which legal skills are enabled in the ⌥L palette. Replaces the old decorative
// `@State legalSkills: Set<String>` (Chinese display strings, no consumer) with a
// real, persisted set of skill **ids** that `LegalSkillRuntime` filters candidates
// against and the 技能平台 toggles write to. This per-skill set is now the ONLY gate —
// the old `legalSkillsEnabled` 全局总开关 (legal/non-legal split) is retired.
//
// `nil` (never set) → the 7 default-enabled built-ins. `[]` (user turned everything
// off) → empty, deliberately distinct from the default. Imported skills (122+) start
// **disabled**, so they only appear after the user explicitly enables them.

public struct EnabledLegalSkillStore {
    public static let defaultsKey = "legal.enabledSkills"
    // (The 2026-06-21 `temporarilyHiddenIDs` soft-hide set is gone: the six hidden-but-on-disk
    // skills were deleted outright in 1.5.0 — the bundle now IS the curated set, so hiding
    // machinery on top of it had nothing left to hide.)

    /// The 7 default-enabled built-in skill ids (one per first-class legal action).
    public static let defaultEnabledIDs: Set<String> = [
        "academic.citation_formatting.cn",       // 引注转换
        "academic.counterargument.cn",           // 反方观点 (卡片 + 多轮对抗)
        "academic.goal_brief.cn",                // 目标七问 (卡片 + 多轮完善)
        "academic.idea_planning.cn",             // 思路推演 (卡片 + 多轮对抗)
        "academic.prompt_optimization.cn",       // 提示词优化 (卡片 + 多轮完善)
        "research.search_strategy.cn",           // 检索策略 (backs 来源辅助检索)
        "verification.fact_check.cn",            // 事实查验 (backs 来源核验)
    ]

    /// Pure resolve so the default/empty distinction is unit-testable without UserDefaults.
    /// `nil` (key absent) → defaults; any array (incl. empty) → exactly that set. A stored id
    /// whose skill no longer ships resolves fine — the registry simply won't find it, so it
    /// renders nowhere and needs no migration.
    public static func resolve(stored: [String]?) -> Set<String> {
        stored.map(Set.init) ?? defaultEnabledIDs
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var enabledIDs: Set<String> {
        Self.resolve(stored: defaults.array(forKey: Self.defaultsKey) as? [String])
    }

    public func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    /// Toggle one skill on/off and persist. Writes a sorted array so storage is stable.
    public func setEnabled(_ enabled: Bool, id: String) {
        var ids = enabledIDs
        if enabled { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.sorted(), forKey: Self.defaultsKey)
    }

    /// Force a skill on (onboarding's mandated 立案评估), preserving the rest.
    public func ensureEnabled(_ id: String) { setEnabled(true, id: id) }
}
