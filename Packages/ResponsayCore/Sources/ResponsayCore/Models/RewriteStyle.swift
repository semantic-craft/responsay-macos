import Foundation

/// How a 重改写 is steered: a built-in `RewriteTone` preset, or an imported /
/// built-in `StylePack` (prompt + few-shot). A pack shapes **register only** —
/// `RewritePromptBuilder` slots it in as the style directive but keeps the
/// same-language / faithfulness / JSON-envelope scaffolding ours, so an
/// untrusted imported system prompt cannot escape it (StylePack spec §1.5;
/// 325 接通最小版 — the rewrite chain can now read the compiled StylePack that
/// import produced but previously discarded).
public enum RewriteStyle: Sendable, Equatable {
    case tone(RewriteTone)
    case pack(StylePack)

    public static let `default` = RewriteStyle.tone(.natural)
}
