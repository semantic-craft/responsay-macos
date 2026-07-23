import Foundation

/// A resolved BYOK LLM target for the App-direct path: which provider, where, which model,
/// the key, and whether 思考(thinking) is on. The app builds this from
/// `ProviderConfigDispatcher.resolve(.llm)` + the `byok.llm.thinking` toggle and hands it to
/// `DirectTextRewriteAPI` (and its 241–244 siblings). Pure data, so the whole LLM path
/// unit-tests without the Keychain or UserDefaults.
public struct LLMEndpoint: Sendable, Equatable {
    public let providerId: String
    public let baseURL: String
    public let model: String
    public let apiKey: String?
    public let thinkingEnabled: Bool

    public init(
        providerId: String,
        baseURL: String,
        model: String,
        apiKey: String?,
        thinkingEnabled: Bool = false
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.thinkingEnabled = thinkingEnabled
    }

    /// Host of the base URL, lowercased (drives custom-endpoint 思考 channel + local detection).
    public var host: String { URL(string: baseURL)?.host?.lowercased() ?? "" }

    /// A localhost runner (Ollama) needs no key; cloud BYOK does.
    public var isLocal: Bool {
        providerId.lowercased() == "ollama" || host == "localhost" || host == "127.0.0.1"
    }

    /// Configured = reachable: base URL + model present, and a key unless local.
    public var isConfigured: Bool {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isLocal || !(apiKey ?? "").isEmpty
    }
}
