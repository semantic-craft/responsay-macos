import Foundation
import Testing
@testable import ResponsayCore

/// Gemini does ASR through the native `:generateContent` endpoint (the audio doc
/// shows no OpenAI-style `/audio/transcriptions`): the audio rides inline as a
/// `inline_data` part and a text part asks for a verbatim transcript. Auth is the
/// Gemini `x-goog-api-key` header, NOT the LLM lane's Bearer. These tests pin the
/// request shape + response parsing without a network.
/// Own stub (not the shared StubURLProtocol) — its mutable statics would race
/// with other suites running in parallel.
private final class GeminiStubProtocol: URLProtocol {
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]
    nonisolated(unsafe) static var requestURL: URL?
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
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

private func geminiStubbedSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [GeminiStubProtocol.self]
    return URLSession(configuration: cfg)
}

@Suite(.serialized)
struct DirectGeminiTranscriptionTests {

    @Test func transcribe_postsToGenerateContentWithInlineAudioAndApiKeyHeader() async throws {
        GeminiStubProtocol.statusCode = 200
        GeminiStubProtocol.responseData =
            #"{"candidates":[{"content":{"parts":[{"text":"你好世界"}]}}]}"#.data(using: .utf8)!
        GeminiStubProtocol.requestHeaders = [:]
        let api = DirectGeminiTranscriptionAPI(
            session: geminiStubbedSession(),
            modelProvider: { "gemini-3.5-flash" },
            apiKeyProvider: { "test-gemini-key" })

        let result = try await api.transcribe(audio: Data([0x01, 0x02]), mimeType: "audio/wav", language: "zh")

        // Endpoint: native custom method, not /audio/transcriptions.
        #expect(GeminiStubProtocol.requestURL?.absoluteString.hasSuffix(
            "models/gemini-3.5-flash:generateContent") == true)
        // Auth: Gemini key header, never Bearer.
        #expect(GeminiStubProtocol.requestHeaders["x-goog-api-key"] == "test-gemini-key")
        #expect(GeminiStubProtocol.requestHeaders["Authorization"] == nil)
        // Audio rides as a base64 inline_data part.
        let body = try #require(JSONSerialization.jsonObject(with: GeminiStubProtocol.requestBody) as? [String: Any])
        let contents = try #require(body["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.compactMap { $0["inline_data"] as? [String: Any] }.first)
        #expect(inline["mime_type"] as? String == "audio/wav")
        #expect(inline["data"] as? String == Data([0x01, 0x02]).base64EncodedString())
        // Parsed transcript + provider tag.
        #expect(result.text == "你好世界")
        #expect(result.provider == "gemini")
        #expect(result.model == "gemini-3.5-flash")
    }

    /// The transcribe-only constraint, the faithful no-punctuation rule, and the
    /// hotword never-insert guard (ADR-0011) must all reach the text part — this
    /// is what stops the LLM from translating/summarising/normalising.
    @Test func transcribe_faithfulAndHotwords_constrainPromptVerbatim() async throws {
        GeminiStubProtocol.statusCode = 200
        GeminiStubProtocol.responseData =
            #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.data(using: .utf8)!
        let api = DirectGeminiTranscriptionAPI(
            session: geminiStubbedSession(),
            hotwordsProvider: { ["沈砚秋", "Responsay"] },
            profileProvider: { .faithful },
            modelProvider: { "gemini-3.1-flash-lite" },
            apiKeyProvider: { "test-gemini-key" })

        _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")

        let prompt = try promptText(from: GeminiStubProtocol.requestBody)
        #expect(prompt.contains("不要翻译"))                 // transcribe-only
        #expect(prompt.contains("不要添加或规整标点"))         // faithful profile
        #expect(prompt.contains("沈砚秋、Responsay"))         // hotwords
        #expect(prompt.contains("不要插入没有说过的词"))       // ADR-0011 never-insert guard
    }

    @Test func transcribe_dictationNoHotwords_promptOmitsHotwordAndPunctuationLines() async throws {
        GeminiStubProtocol.statusCode = 200
        GeminiStubProtocol.responseData =
            #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.data(using: .utf8)!
        let api = DirectGeminiTranscriptionAPI(
            session: geminiStubbedSession(),
            hotwordsProvider: { [] },
            profileProvider: { .dictation },
            modelProvider: { "gemini-3.5-flash" },
            apiKeyProvider: { "test-gemini-key" })

        _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "en")

        let prompt = try promptText(from: GeminiStubProtocol.requestBody)
        #expect(prompt.contains("Transcribe the speech"))   // verbatim core present
        #expect(!prompt.contains("terms may appear"))       // no hotword line
        #expect(!prompt.contains("punctuation"))            // no faithful line
    }

    /// A blocked/empty answer (safety filter, silence) yields no candidate parts —
    /// surface a clear "empty" error rather than returning "".
    @Test func transcribe_emptyCandidates_throws() async throws {
        GeminiStubProtocol.statusCode = 200
        GeminiStubProtocol.responseData = #"{"candidates":[]}"#.data(using: .utf8)!
        let api = DirectGeminiTranscriptionAPI(
            session: geminiStubbedSession(),
            apiKeyProvider: { "test-gemini-key" })

        await #expect(throws: (any Error).self) {
            _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        }
    }

    @Test func transcribe_missingKey_throwsBeforeNetwork() async throws {
        let api = DirectGeminiTranscriptionAPI(
            session: geminiStubbedSession(),
            apiKeyProvider: { "  " })
        await #expect(throws: (any Error).self) {
            _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        }
    }

    private func promptText(from body: Data) throws -> String {
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        return try #require(parts.compactMap { $0["text"] as? String }.first)
    }
}
