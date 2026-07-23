import Foundation

/// 462 — resolves the effective polish styleHint that `PolishPromptBuilder` appends after the
/// faithfulness red lines. Precedence (PRD §3): an explicitly-activated 日常办公 pack OVERRIDES the
/// auto per-app register layer; with no pack, the frontmost app drives a register guidance block.
/// `nil` → plain tidy (the prompt stays byte-identical to today). The block only adjusts 语体/measure;
/// it never overrides the same-language / faithfulness / output-format rules above it.
public enum RegisterPromptHint {
    public static func resolve(
        activePackHint: String? = nil,
        bundleID: String?,
        appName: String? = nil,
        domain: String? = nil,
        legalSeeds: Set<String> = []
    ) -> String? {
        if let pack = activePackHint, !pack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pack
        }
        let tier = RegisterTierClassifier(legalSeeds: legalSeeds)
            .tier(bundleID: bundleID, appName: appName, domain: domain)
        guard tier != .neutral else { return nil }
        let label = appName ?? bundleID ?? ""
        // 468 A/B: the multi-row ceiling table was inert on the polish path (the faithful-tidy contract
        // dominates), so it was dropped — just the floor directive + the conservative red line remain.
        // Real per-app register adaptation belongs on heavy-rewrite, not light polish (468 findings).
        return [
            "按当前应用/场景调整语体（register；只调语气与措辞，永远服从上方的红线）：",
            "- 当前应用：\(label)。该类应用通常的语体：\(tier.guidance)",
            "- 红线：只调语体/措辞，不增删用户没说的内容、不改变其立场或确定性；与上方同语种、忠实、输出格式规则冲突时一律以上方为准。",
        ].joined(separator: "\n")
    }
}
