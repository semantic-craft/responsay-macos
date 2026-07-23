import Foundation

/// The visible cloud / local / no-key route for the Intent-aware compiler (#566, spec decisions
/// 30/59). Derived purely from the already-resolved BYOK `LLMEndpoint` — the user "chooses local"
/// simply by pointing their configured LLM endpoint at a local runner (Ollama / an OpenAI-compatible
/// `localhost` server); there is no separate selector and no revived backend. Settings and the
/// capsule show this so the user knows whether their utterance goes to the cloud or stays on device,
/// and which provider receives it. Content-free: only the provider id, never a key or URL.
public enum IntentCompilerRoute: Equatable, Sendable {
    /// A configured cloud BYOK endpoint (a key-bearing remote provider).
    case cloud(provider: String)
    /// A configured local runner (`endpoint.isLocal`) — the request never leaves the device.
    case local(provider: String)
    /// No usable endpoint: missing model / base URL, or a cloud provider with no key.
    case unavailable

    /// Classify the resolved endpoint. An unconfigured endpoint (or `nil`) is `.unavailable`; a
    /// configured one is `.local` when `isLocal`, else `.cloud`.
    public static func classify(_ endpoint: LLMEndpoint?) -> IntentCompilerRoute {
        guard let endpoint, endpoint.isConfigured else { return .unavailable }
        return endpoint.isLocal
            ? .local(provider: endpoint.providerId)
            : .cloud(provider: endpoint.providerId)
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    /// A short, content-free label for settings / capsule (spec decision 59: local vs cloud + which
    /// provider). Never carries the base URL or key.
    public var displayLabel: String {
        switch self {
        case .cloud(let provider): return "云端 · \(provider)"
        case .local(let provider): return "本机 · \(provider)"
        case .unavailable: return "未配置模型"
        }
    }
}
