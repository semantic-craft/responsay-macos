import Foundation
import ResponsayCore

enum CapabilityProbeRequestBuilder {
    static func modelsRequest(
        providerId: String,
        capability: ModelCapability,
        baseURL: String,
        apiKey: String
    ) -> URLRequest? {
        guard supportsRemoteModelsRequest(providerId: providerId, capability: capability) else {
            return nil
        }
        guard let url = URL(string: ProviderModelList.modelsURL(base: baseURL)) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (field, value) in authHeaders(
            providerId: providerId,
            capability: capability,
            baseURL: baseURL,
            apiKey: apiKey
        ) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func supportsRemoteModelsRequest(providerId: String, capability: ModelCapability) -> Bool {
        // openspeech.bytedance.com (火山引擎 speech: volcengine-flash ASR + volcengine-tts TTS)
        // is a speech API with no OpenAI-style /models listing — a GET there 404s. Validate
        // these locally (validatePresetOnly) instead of probing a nonexistent endpoint.
        // qwen-asr-flash now fronts the 千问极速实时 WSS engine (wss://…/api-ws/v1/realtime);
        // a `/models` GET can't run against a wss base, so it's preset-validated too.
        let id = providerId.lowercased()
        if id == "volcengine-flash", capability == .asr { return false }
        if id == "qwen-asr-flash", capability == .asr { return false }
        if id == "volcengine-tts", capability == .tts { return false }
        return true
    }

    static func authHeaders(
        providerId: String,
        capability: ModelCapability,
        baseURL: String,
        apiKey: String
    ) -> [String: String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [:] }
        if ProviderModelList.isGeminiBase(baseURL) {
            return ["x-goog-api-key": key]
        }
        if providerId.lowercased() == "mimo" {
            switch capability {
            case .llm:
                return ["api-key": key]
            case .asr, .tts:
                return ["api-key": key]
            }
        }
        return ["Authorization": "Bearer \(key)"]
    }
}
