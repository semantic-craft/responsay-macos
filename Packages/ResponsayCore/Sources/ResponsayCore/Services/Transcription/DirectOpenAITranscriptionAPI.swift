import Foundation

public struct DirectOpenAITranscriptionAPI: TranscriptionAPI {
    /// OpenAI caps an uploaded audio file at 25 MB; 20 MB leaves headroom for
    /// the multipart framing around it.
    public static let defaultMaxAudioBytes = 20_000_000

    private let baseURL: URL
    private let session: URLSession
    private let maxAudioBytes: Int
    private let hotwordsProvider: @Sendable () -> [String]
    private let profileProvider: @Sendable () -> SpeechCaptureProfile
    private let modelProvider: @Sendable () -> String
    private let apiKeyProvider: @Sendable () -> String

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        session: URLSession = .shared,
        maxAudioBytes: Int = DirectOpenAITranscriptionAPI.defaultMaxAudioBytes,
        hotwordsProvider: @escaping @Sendable () -> [String] = { [] },
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        modelProvider: @escaping @Sendable () -> String = { "whisper-1" },
        apiKeyProvider: @escaping @Sendable () -> String = {
            (UserDefaults.standard.string(forKey: "openaiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
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

        let key = apiKeyProvider()
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置 OpenAI API Key。请在设置中配置。")
        }

        let prompt = TranscriptionBiasPrompt.build(profile: profileProvider(), hotwords: hotwordsProvider())
        let request = WhisperMultipartRequest.build(
            baseURL: baseURL, key: key, audio: audio, model: modelProvider(),
            prompt: prompt, language: language, mimeType: mimeType)

        let (data, response) = try await session.data(for: request)
        try ASRHTTPGuards.validate(response, data: data, brand: "OpenAI ASR")

        let json = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let text = json.text ?? ""
        try ASRHTTPGuards.nonEmpty(text, brand: "OpenAI ASR")

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelProvider(),
            language: language,
            provider: "openai"
        )
    }
}

private struct OpenAIResponse: Decodable {
    let text: String?
}
