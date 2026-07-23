import Foundation

public struct DirectMimoTranscriptionAPI: StreamingTranscriptionAPI {
    private let baseURL: URL
    private let session: URLSession
    private let maxAudioBytes: Int
    private let modelProvider: @Sendable () -> String
    private let apiKeyProvider: @Sendable () -> String

    public init(
        baseURL: URL = URL(string: "https://token-plan-cn.xiaomimimo.com/v1")!,
        session: URLSession = .shared,
        // MiMo's 10 MB limit applies to the *base64-encoded* payload
        // (xiaomi_mimo_asr.md); base64 inflates by 4/3, so cap raw at 7.5 MB.
        maxAudioBytes: Int = 7_500_000,
        hotwordsProvider: @escaping @Sendable () -> [String] = { [] },
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        modelProvider: @escaping @Sendable () -> String = { "mimo-v2.5-asr" },
        apiKeyProvider: @escaping @Sendable () -> String = {
            (UserDefaults.standard.string(forKey: "mimoKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAudioBytes = maxAudioBytes
        // MiMo ASR rejects `text` content parts, so these injected hint sources
        // are intentionally ignored here. Hotword hard-match still runs after
        // transcription in the app router.
        _ = hotwordsProvider
        _ = profileProvider
        self.modelProvider = modelProvider
        self.apiKeyProvider = apiKeyProvider
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        let languageOption = Self.normalizedLanguageOption(language)
        let request = try makeRequest(
            audio: audio,
            mimeType: mimeType,
            languageOption: languageOption,
            stream: false)

        let (data, response) = try await session.data(for: request)
        try ASRHTTPGuards.validate(response, data: data, brand: "MiMo ASR")

        let json = try JSONDecoder().decode(MiMoResponse.self, from: data)
        let text = MiMoTranscriptCleaner.clean(json.choices.first?.message.content ?? "")
        try ASRHTTPGuards.nonEmpty(text, brand: "MiMo ASR")

        return TranscriptionResult(
            text: text,
            model: modelProvider(),
            language: languageOption,
            provider: "mimo"
        )
    }

    public func streamTranscription(
        audio: Data,
        mimeType: String,
        language: String
    ) -> AsyncThrowingStream<TextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        audio: audio,
                        mimeType: mimeType,
                        languageOption: Self.normalizedLanguageOption(language),
                        stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: CoachAPIError.message("MiMo ASR 网络错误"))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: CoachAPIError.message("MiMo ASR \(http.statusCode)"))
                        return
                    }
                    // mimo-v2.5-asr streams a <think>…</think>\n<lang> preamble token by
                    // token before the transcript. Cleaning it incrementally would flash
                    // tag fragments into the capsule, so buffer the raw content and emit the
                    // cleaned transcript once, when the segment completes.
                    var rawAccum = ""
                    for try await line in bytes.lines {
                        guard let eventData = MiMoASRStreamDecoder.eventData(from: line) else { continue }
                        switch MiMoASRStreamDecoder.decode(eventData) {
                        case .delta(let text):
                            rawAccum += text
                        case .done:
                            let cleaned = MiMoTranscriptCleaner.clean(rawAccum)
                            if !cleaned.isEmpty { continuation.yield(.delta(cleaned)) }
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        case .failure(let message):
                            continuation.yield(.failed(message))
                            continuation.finish()
                            return
                        case .ignored:
                            continue
                        }
                    }
                    let cleaned = MiMoTranscriptCleaner.clean(rawAccum)
                    if !cleaned.isEmpty { continuation.yield(.delta(cleaned)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(
        audio: Data,
        mimeType: String,
        languageOption: String,
        stream: Bool
    ) throws -> URLRequest {
        try ASRHTTPGuards.audioSize(audio, max: maxAudioBytes)

        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置小米 MIMO 的 API Key。请在设置中配置。")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 120

        let base64Audio = audio.base64EncodedString()
        let dataURI = "data:\(mimeType);base64,\(base64Audio)"
        let payload: [String: Any] = [
            "model": modelProvider(),
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_audio", "input_audio": ["data": dataURI]]
                    ]
                ]
            ],
            "asr_options": ["language": languageOption],
            "stream": stream
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private static func normalizedLanguageOption(_ language: String) -> String {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("zh") { return "zh" }
        if value.hasPrefix("en") { return "en" }
        if value == "auto" { return "auto" }
        return "auto"
    }
}

private struct MiMoResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
