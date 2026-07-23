import Foundation

/// Provider-specific streaming request extras for OpenAI-compatible `/chat/completions`.
/// Qwen/DashScope only returns token usage in the final streaming chunk when requested.
enum LLMStreamOptionsControl {
    static func extraBody(providerId: String, baseURLHost: String) -> [String: Any] {
        let caps = LLMProviderCapabilities.resolve(providerId: providerId, baseURLHost: baseURLHost)
        guard caps.supportsStreamUsage else { return [:] }
        return ["stream_options": ["include_usage": true]]
    }
}
