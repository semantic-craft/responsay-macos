import Foundation

/// The bundled 「轻度润色」 skill (`style.light_polish.cn`) IS the behaviour of the 轻度润色 改写档
/// (2026-06-16 merge — it's no longer a 日常办公 selectable). The polish prompt injects its
/// instructions so 轻度润色 always runs on the skill:
/// - batch: `PolishPromptBuilder` (JSON `{text,changes}`).
/// Resolved + cached once from the bundle; nil → the builders keep their built-in tidy steering only.
enum PolishTidySkill {
    /// The skill's instruction body, loaded + cached once. nil if the bundle/skill is unavailable
    /// (the polish prompt then degrades to the assembler's built-in 轻改写 steering — still works).
    static let body: String? = {
        (try? StylePackRegistry.bundled())?.pack(id: "style.light_polish.cn")?.systemPrompt
    }()

    /// The steering block appended to a polish system prompt. Empty when the skill is unavailable,
    /// so a caller can `if !isEmpty { append }`. The output-format / same-language / faithfulness
    /// rules built by the assembler stay authoritative — this only enriches HOW the tidy is done.
    static func steeringSection() -> String {
        guard let body, !body.isEmpty else { return "" }
        return "整理细则（严格按以下「智能整理」技能执行；上方关于同一语种 / 忠实 / 输出格式的规则优先）：\n\(body)"
    }
}
