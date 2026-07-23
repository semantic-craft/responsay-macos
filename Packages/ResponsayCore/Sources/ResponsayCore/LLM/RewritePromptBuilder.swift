import Foundation

/// Swift port of the old Node backend's `buildRewritePrompt` (重改写). App-direct path (epic 238,
/// tracer 239): the rewrite prompt lives on the client so the app calls the provider straight.
/// This file is the source of truth now — the backend copy was deleted with the backend
/// (2026-06-11, ADR-0029). 重改写 = same-language heavy rewrite: may restructure freely,
/// never translates, invents nothing.
enum RewritePromptBuilder {
    /// Legacy tone overload — kept so every existing call site is unaffected.
    static func build(text: String, tone: RewriteTone) -> (system: String, user: String) {
        build(text: text, style: .tone(tone))
    }

    /// 325 接通最小版: a `RewriteStyle` may be a built-in tone OR an imported/
    /// built-in StylePack. The pack's prompt + few-shot slot into the style seam
    /// only; the same-language / faithfulness rules (above it) and the JSON
    /// output envelope (below it) stay ours, so an untrusted pack prompt is
    /// sandwiched and cannot override them. For `.tone` the output is
    /// byte-identical to the pre-325 builder (the few-shot section is empty and
    /// filtered out).
    static func build(text: String, style: RewriteStyle, context: String? = nil) -> (system: String, user: String) {
        TextTransformPromptAssembler.build(
            action: .rewrite(style: style),
            text: text,
            input: .selectedText,
            output: .jsonTextChanges,
            options: .init(context: context))
    }

    /// The style directive that sits between our faithfulness rules and the output
    /// envelope. A built-in tone is a one-line directive; an imported/built-in pack
    /// injects its own system prompt, explicitly scoped to register-only so it
    /// cannot override the hard rules around it (defense in depth — the pack prompt
    /// is untrusted input).
    static func styleSection(_ style: RewriteStyle) -> String {
        TextTransformPromptAssembler.styleSection(style)
    }

    /// Few-shot demonstrations a rewrite-tier pack carries (empty → omitted, so the
    /// tone path is byte-identical to the pre-325 builder). Examples teach register,
    /// not content — the faithfulness rules still forbid importing their facts.
    static func fewShotSection(_ style: RewriteStyle) -> String {
        TextTransformPromptAssembler.fewShotSection(style)
    }

    /// 改写风格 directive — the Layer-2 axis (mirrors backend `rewriteToneDirective`).
    static func toneDirective(_ tone: RewriteTone) -> String {
        TextTransformPromptAssembler.toneDirective(tone)
    }
}
