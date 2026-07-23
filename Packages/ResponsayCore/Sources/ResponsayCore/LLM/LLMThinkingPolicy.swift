import Foundation

/// What an LLM call is *for* — decides whether the model's "thinking"/reasoning channel
/// is allowed. (435)
public enum LLMThinkingPurpose: Sendable {
    /// Structured text rewrite: express / polish / rewrite / translate / legal skills.
    case rewrite
    /// Open-ended chat: the voice assistant / 任意提问.
    case chat
}

/// The single decision for whether an LLM request enables thinking. Structured rewrite is
/// **always** thinking-off — it's slow and adds nothing for a JSON-shaped rewrite — and is
/// decoupled from the user's global 思考 toggle, which is reserved for open chat. (435)
public enum LLMThinkingPolicy {
    public static func thinkingEnabled(purpose: LLMThinkingPurpose, globalToggle: Bool) -> Bool {
        switch purpose {
        case .rewrite: return false        // always thinking-off, regardless of the toggle
        case .chat: return globalToggle     // open chat honors the user's global 思考 toggle
        }
    }
}
