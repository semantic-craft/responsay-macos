import Foundation

/// Provider-specific streaming request extras for OpenAI-compatible `/chat/completions`.
/// Responses returns usage on `response.completed`, so Qwen no longer needs this Chat-only field.
enum LLMStreamOptionsControl {
    static func extraBody(providerId: String, baseURLHost: String) -> [String: Any] {
        let caps = LLMProviderCapabilities.resolve(providerId: providerId, baseURLHost: baseURLHost)
        guard caps.supportsStreamUsage else { return [:] }
        return ["stream_options": ["include_usage": true]]
    }
}
