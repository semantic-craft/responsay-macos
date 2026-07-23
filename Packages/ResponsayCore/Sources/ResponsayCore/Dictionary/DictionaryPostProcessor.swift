import Foundation

/// Applies dictionary rules at the **final** ASR transcript only, feeding the
/// corrected text downstream to the LLM (polish / coach / legal skill).
///
/// Invariants (issue 160; ADR + issue 080 log-minimization):
/// - ASR partials stream straight through — never force-corrected.
/// - Only the final transcript has rules applied.
/// - Logs carry counts, never the raw transcript.
public struct DictionaryPostProcessor: Sendable {
    private let engine: DictionaryRuleEngine
    private let rules: [DictionaryRule]

    public init(rules: [DictionaryRule], engine: DictionaryRuleEngine = DictionaryRuleEngine()) {
        self.rules = rules
        self.engine = engine
    }

    /// A partial hypothesis passes through unchanged — correcting a still-moving
    /// transcript would fight the recognizer. Explicit no-op to document the rule.
    public func partial(_ text: String) -> String { text }

    /// Apply rules to the final transcript. `result.corrected` is what feeds the
    /// downstream LLM; `result.edits` powers hit counting + the 词典 UI.
    public func finalTranscript(
        _ text: String,
        context: DictionaryContext = DictionaryContext()
    ) -> DictionaryApplyResult {
        engine.apply(to: text, rules: rules, context: context)
    }

    /// A log-safe one-liner: counts only, never any transcript content.
    public static func redactedLog(_ result: DictionaryApplyResult) -> String {
        "dictionary: \(result.totalHits) hit(s) across \(result.firedRuleIDs.count) rule(s)"
    }
}
