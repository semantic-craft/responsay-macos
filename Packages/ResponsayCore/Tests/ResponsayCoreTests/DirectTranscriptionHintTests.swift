import Foundation
import Testing
@testable import ResponsayCore

/// 猎虫① H9 — the hotword weak hint (ADR-0011 keeps it alongside hard-match)
/// and the capture profile must actually reach the request body when the
/// providers are injected; they were silently dropped at the app-direct
/// migration because no call site passed `hotwordsProvider`/`profileProvider`.
/// MiMo is the exception: its ASR gateway rejects `text` content parts, so only
/// the app-side hard-match can use the hotword dictionary after transcription.
/// Own stub (not the shared StubURLProtocol) — its mutable statics would race
/// with other suites running in parallel.
private final class HintStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func hintStubbedSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [HintStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

@Suite(.serialized)
struct DirectTranscriptionHintTests {

    @Test func openAI_faithfulProfileAndHotwords_landInPrompt() async throws {
        HintStubURLProtocol.responseData = #"{"text":"ok"}"#.data(using: .utf8)!
        HintStubURLProtocol.requestHeaders = [:]
        let api = DirectOpenAITranscriptionAPI(
            session: hintStubbedSession(),
            hotwordsProvider: { ["Qwen3-ASR", "Responsay"] },
            profileProvider: { .faithful },
            modelProvider: { "gpt-4o-transcribe" },
            apiKeyProvider: { "test-key" })

        _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")

        let body = String(decoding: HintStubURLProtocol.requestBody, as: UTF8.self)
        #expect(body.contains("请尽量保持原样转写"))
        #expect(body.contains("以下是一些相关的热词或术语：Qwen3-ASR, Responsay"))
        #expect(body.contains("不要插入没有说过的词"))   // ADR-0011 never-insert guard
        #expect(HintStubURLProtocol.requestHeaders["Authorization"] == "Bearer test-key")
    }

    @Test func openAI_dictationNoHotwords_sendsNoPromptHint() async throws {
        HintStubURLProtocol.responseData = #"{"text":"ok"}"#.data(using: .utf8)!
        let api = DirectOpenAITranscriptionAPI(
            session: hintStubbedSession(),
            hotwordsProvider: { [] },
            profileProvider: { .dictation },
            modelProvider: { "gpt-4o-transcribe" },
            apiKeyProvider: { "test-key" })

        _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")

        let body = String(decoding: HintStubURLProtocol.requestBody, as: UTF8.self)
        #expect(!body.contains("热词"))
        #expect(!body.contains(#"name="prompt""#))
    }

    @Test func mimo_usesInputAudioOnlyBecauseGatewayRejectsTextParts() async throws {
        HintStubURLProtocol.responseData =
            #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        HintStubURLProtocol.requestHeaders = [:]
        let api = DirectMimoTranscriptionAPI(
            session: hintStubbedSession(),
            hotwordsProvider: { ["沈砚秋"] },
            profileProvider: { .faithful },
            modelProvider: { "mimo-v2.5-asr" },
            apiKeyProvider: { "settings-mimo-key" })

        let result = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")

        let body = try #require(JSONSerialization.jsonObject(with: HintStubURLProtocol.requestBody) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let asrOptions = try #require(body["asr_options"] as? [String: Any])
        #expect(content.count == 1)
        #expect(content.first?["type"] as? String == "input_audio")
        #expect(asrOptions["language"] as? String == "zh")
        #expect(body["temperature"] == nil)
        #expect(String(decoding: HintStubURLProtocol.requestBody, as: UTF8.self).contains("沈砚秋") == false)
        #expect(HintStubURLProtocol.requestHeaders["api-key"] == "settings-mimo-key")
        #expect(HintStubURLProtocol.requestHeaders["Authorization"] == nil)
        #expect(result.provider == "mimo")
    }

    @Test func mimo_normalizesOfficialLanguageOptions() async throws {
        HintStubURLProtocol.responseData =
            #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let api = DirectMimoTranscriptionAPI(
            session: hintStubbedSession(),
            modelProvider: { "mimo-v2.5-asr" },
            apiKeyProvider: { "settings-mimo-key" })

        let english = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "en-US")
        var body = try #require(JSONSerialization.jsonObject(with: HintStubURLProtocol.requestBody) as? [String: Any])
        var asrOptions = try #require(body["asr_options"] as? [String: Any])
        #expect(asrOptions["language"] as? String == "en")
        #expect(english.language == "en")

        let auto = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "de-DE")
        body = try #require(JSONSerialization.jsonObject(with: HintStubURLProtocol.requestBody) as? [String: Any])
        asrOptions = try #require(body["asr_options"] as? [String: Any])
        #expect(asrOptions["language"] as? String == "auto")
        #expect(auto.language == "auto")
    }

    @Test func mimo_streamingASRDecodesChatCompletionChunks() async throws {
        HintStubURLProtocol.responseData = """
        data: {"choices":[{"delta":{"content":"","role":"assistant"},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":"Good","role":null},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":" morning","role":null},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":null,"role":null},"finish_reason":"stop","index":0}],"object":"chat.completion.chunk","usage":null}

        data: {"choices":[],"object":"chat.completion.chunk","usage":{"seconds":4}}

        data: [DONE]
        """.data(using: .utf8)!
        let api = DirectMimoTranscriptionAPI(
            session: hintStubbedSession(),
            modelProvider: { "mimo-v2.5-asr" },
            apiKeyProvider: { "settings-mimo-key" })

        var events: [TextStreamEvent] = []
        for try await event in api.streamTranscription(audio: Data([0x01]), mimeType: "audio/wav", language: "en-US") {
            events.append(event)
        }

        let body = try #require(JSONSerialization.jsonObject(with: HintStubURLProtocol.requestBody) as? [String: Any])
        let asrOptions = try #require(body["asr_options"] as? [String: Any])
        // mimo-v2.5-asr prefixes the transcript with a <think>…</think>\n<lang>
        // preamble that streams token by token; cleaning it incrementally would flash
        // tag fragments into the capsule, so the chunks are buffered and the cleaned
        // transcript is emitted once.
        #expect(events == [.delta("Good morning"), .done])
        #expect(body["stream"] as? Bool == true)
        #expect(asrOptions["language"] as? String == "en")
        #expect(HintStubURLProtocol.requestHeaders["Accept"] == "text/event-stream")
    }

    // The reasoning-model noise (<think>…</think>\n<lang> …, plus the malformed
    // leading `think>` from the pre-filled template) must be stripped from the
    // streamed transcript — verbatim shape of the live Token-Plan response.
    @Test func mimo_streamingASRStripsReasoningPreamble() async throws {
        HintStubURLProtocol.responseData = """
        data: {"choices":[{"delta":{"content":"think>\\n<chinese>","role":"assistant"},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":" Hello there","role":null},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":null,"role":null},"finish_reason":"stop","index":0}],"object":"chat.completion.chunk"}

        data: [DONE]
        """.data(using: .utf8)!
        let api = DirectMimoTranscriptionAPI(
            session: hintStubbedSession(),
            modelProvider: { "mimo-v2.5-asr" },
            apiKeyProvider: { "settings-mimo-key" })

        var events: [TextStreamEvent] = []
        for try await event in api.streamTranscription(audio: Data([0x01]), mimeType: "audio/wav", language: "en-US") {
            events.append(event)
        }

        #expect(events == [.delta("Hello there"), .done])
    }

}
