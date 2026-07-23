import Foundation

/// 315 — per-usage sandbox demo copy. The sandbox's REAL dictation mechanism
/// (312) is untouched; only the suggested sentence and the scripted-fallback
/// transcript adapt to the chosen 主要用途, so a legal user rehearses a legal
/// dictation line and an English learner dictates English.
struct SandboxDemoScript: Equatable {
    /// Shown next to the tap dictation button:「比如：…」(real dictation mode).
    let suggestion: String
    /// Scripted fallback: what the fake capsule "hears".
    let spoken: String
    /// Scripted fallback: what lands in the 模拟编辑器.
    let inserted: String

    static func demo(for usage: Usage) -> SandboxDemoScript {
        switch usage {
        case .legal:
            SandboxDemoScript(
                suggestion: "被告未按合同约定交货，已构成根本违约",
                spoken: "被告未按合同约定交货，已构成根本违约",
                inserted: "被告未按合同约定交货，已构成根本违约。")
        case .general:
            SandboxDemoScript(
                suggestion: "今天天气真不错",
                spoken: "今天天气真不错",
                inserted: "今天天气真不错。")
        case .english:
            SandboxDemoScript(
                suggestion: "I want to make my English sound natural",
                spoken: "I want to make my English sound natural",
                inserted: "I want to make my English sound natural.")
        }
    }
}
