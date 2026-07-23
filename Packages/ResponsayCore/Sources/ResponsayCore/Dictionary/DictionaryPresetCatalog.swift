import Foundation

/// Built-in scene presets (issue 159): each bundles correction rules + hotwords
/// the user can multi-select and batch-apply. Rules have stable ids so presets
/// reference them and per-preset hit stats roll up deterministically.
public enum DictionaryPresetCatalog {
    private static func uuid(_ string: String) -> UUID { UUID(uuidString: string) ?? UUID() }

    // MARK: Stable rule ids

    static let idArticleSpacing = uuid("A0000000-0000-0000-0000-000000000001")
    static let idPiplTypo       = uuid("A0000000-0000-0000-0000-000000000002")
    static let idDataLawTypo    = uuid("A0000000-0000-0000-0000-000000000003")
    static let idPiplAcronym    = uuid("A0000000-0000-0000-0000-000000000004")
    static let idArxivCase      = uuid("A0000000-0000-0000-0000-000000000005")
    static let idEtAl           = uuid("A0000000-0000-0000-0000-000000000006")

    // MARK: Preset ids

    public static let legalPaperID: ScenePresetID = "legal.paper"
    public static let dataLawID: ScenePresetID = "data.law"
    public static let englishStudyID: ScenePresetID = "english.study"

    // MARK: Rule corpus

    public static let rules: [DictionaryRule] = [
        DictionaryRule(id: idArticleSpacing, pattern: "第 {num} 条", replacement: "第{num}条",
                       ruleType: .wildcardCorrection),
        DictionaryRule(id: idPiplTypo, pattern: "个人信息保护发", replacement: "个人信息保护法",
                       ruleType: .exactCorrection),
        DictionaryRule(id: idDataLawTypo, pattern: "数据安全发", replacement: "数据安全法",
                       ruleType: .exactCorrection),
        DictionaryRule(id: idPiplAcronym, pattern: "{letter} {letter} {letter} {letter}",
                       replacement: "{letter}{letter}{letter}{letter}", ruleType: .wildcardCorrection),
        DictionaryRule(id: idArxivCase, pattern: "Arxiv", replacement: "arXiv", ruleType: .exactCorrection),
        DictionaryRule(id: idEtAl, pattern: "et al", replacement: "et al.", ruleType: .exactCorrection),
    ]

    // MARK: Presets

    public static let presets: [ScenePreset] = [
        ScenePreset(id: legalPaperID, name: "法律论文",
                    rules: [idArticleSpacing, idPiplTypo],
                    hotwords: ["CLSCI", "SSRN", "北大法宝"]),
        ScenePreset(id: dataLawID, name: "数据法",
                    rules: [idDataLawTypo, idPiplAcronym, idPiplTypo],
                    hotwords: ["PIPL", "GDPR", "数据安全法", "个人信息保护法"]),
        ScenePreset(id: englishStudyID, name: "英语学习",
                    rules: [idArxivCase, idEtAl],
                    hotwords: ["arXiv", "et al.", "DOI"]),
    ]

    public static func preset(id: ScenePresetID) -> ScenePreset? {
        presets.first { $0.id == id }
    }

    // MARK: Multi-select batch apply

    /// The deduplicated, enabled rule set for a multi-selection of presets —
    /// feed this straight into `DictionaryRuleEngine`.
    public static func rules(forEnabledPresets enabled: Set<ScenePresetID>) -> [DictionaryRule] {
        let ruleIDs = presets.filter { enabled.contains($0.id) }.flatMap(\.rules)
        var seen = Set<UUID>()
        var resolved: [DictionaryRule] = []
        for ruleID in ruleIDs where !seen.contains(ruleID) {
            if let rule = rules.first(where: { $0.id == ruleID }) {
                seen.insert(ruleID)
                resolved.append(rule)
            }
        }
        return resolved
    }

    /// Hotwords contributed by a multi-selection of presets (deduplicated).
    public static func hotwords(forEnabledPresets enabled: Set<ScenePresetID>) -> [String] {
        var seen = Set<String>()
        var resolved: [String] = []
        for preset in presets where enabled.contains(preset.id) {
            for word in preset.hotwords where !seen.contains(word) {
                seen.insert(word)
                resolved.append(word)
            }
        }
        return resolved
    }

    // MARK: Per-preset hit stats

    /// Total dictionary hits attributable to each preset for an apply result.
    public static func hitStats(_ result: DictionaryApplyResult) -> [ScenePresetID: Int] {
        var stats: [ScenePresetID: Int] = [:]
        for preset in presets {
            stats[preset.id] = preset.rules.reduce(0) { $0 + result.hitCount(for: $1) }
        }
        return stats
    }
}
