import Foundation

/// App-direct (BYOK) ASR via Google Gemini. Unlike Whisper-style providers,
/// Gemini exposes NO `/audio/transcriptions` endpoint: transcription is the
/// multimodal `:generateContent` call with the clip as an `inline_data` part and
/// a text part asking for a verbatim transcript. Because it is an LLM "reading"
/// the audio, the prompt must hard-constrain it to transcribe-only (no
/// translation, summary, or commentary) — see `GeminiTranscriptionPrompt`.
///
/// Auth is the Gemini `x-goog-api-key` header (the same key the LLM/TTS lanes
/// use), NOT the OpenAI-compat Bearer. Base URL is the native host; the model and
/// custom method are appended per request.
public struct DirectGeminiTranscriptionAPI: TranscriptionAPI {
    private let baseURL: URL
    private let session: URLSession
    private let maxAudioBytes: Int
    private let hotwordsProvider: @Sendable () -> [String]
    private let profileProvider: @Sendable () -> SpeechCaptureProfile
    private let modelProvider: @Sendable () -> String
    private let apiKeyProvider: @Sendable () -> String

    public init(
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!,
        session: URLSession = .shared,
        // Gemini caps a single inline request at 20 MB *total* (audio doc); base64
        // inflates by 4/3, so cap raw audio at 15 MB. The capture service segments
        // well below this, so the guard only trips on a pathological single clip.
        maxAudioBytes: Int = 15_000_000,
        hotwordsProvider: @escaping @Sendable () -> [String] = { [] },
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        modelProvider: @escaping @Sendable () -> String = { "gemini-3.1-flash-lite" },
        apiKeyProvider: @escaping @Sendable () -> String = { "" }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAudioBytes = maxAudioBytes
        self.hotwordsProvider = hotwordsProvider
        self.profileProvider = profileProvider
        self.modelProvider = modelProvider
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        try ASRHTTPGuards.audioSize(audio, max: maxAudioBytes)
        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置 Gemini API Key。请在设置中配置。")
        }

        let model = modelProvider()
        // `:generateContent` is a custom method on the model resource — append by
        // string so the colon isn't percent-encoded into a path component.
        guard let url = URL(string: baseURL.absoluteString + "models/\(model):generateContent") else {
            throw CoachAPIError.message("Gemini ASR 端点无效。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120

        let prompt = GeminiTranscriptionPrompt.build(
            language: language,
            profile: profileProvider(),
            hotwords: hotwordsProvider())
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": mimeType, "data": audio.base64EncodedString()]],
                    ["text": prompt],
                ],
            ]],
            // Deterministic, transcribe-only: temperature 0 keeps the model from
            // paraphrasing the speech.
            "generationConfig": ["temperature": 0],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try ASRHTTPGuards.validate(response, data: data, brand: "Gemini ASR")

        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let text = decoded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        try ASRHTTPGuards.nonEmpty(text, brand: "Gemini ASR")
        return TranscriptionResult(text: text, model: model, language: language, provider: "gemini")
    }
}

/// Minimal decode of the `:generateContent` response — joins every text part of
/// the first candidate. Other fields (safety ratings, usage) are ignored.
private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?

    var transcript: String {
        (candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
    }
}
