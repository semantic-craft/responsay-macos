import XCTest
@testable import ResponsayMac
import ResponsayCore
@testable import ResponsaySpeech

/// 195 — BYOK direct cloud TTS: audio decoding, per-adapter request shapes, and
/// the engine round-trip via a stub URLProtocol. Test standard T1 (no network).
final class CloudTTSTests: XCTestCase {
    // Audio fixtures: shared `TTSTestAudio` (was duplicated per file).
    private func makeWAV(_ samples: [Float], sampleRate: Int = 24_000) -> Data {
        TTSTestAudio.wav(samples, sampleRate: sampleRate)
    }
    private func pcm16Base64(_ samples: [Float]) -> String { TTSTestAudio.pcm16Base64(samples) }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    // MARK: - decoder

    func testDecodeWAVRoundTrip() throws {
        let speech = try CloudTTSAudioDecoder.wav(makeWAV([0, 0.5, -0.5, 1.0], sampleRate: 16_000))
        XCTAssertEqual(speech.sampleRate, 16_000)
        XCTAssertEqual(speech.samples.count, 4)
        XCTAssertEqual(speech.samples[1], 0.5, accuracy: 0.001)
    }

    func testDecodePCM16() throws {
        let b64 = pcm16Base64([0, 0.25, -0.25])
        let speech = try CloudTTSAudioDecoder.pcm16(Data(base64Encoded: b64)!, sampleRate: 24_000)
        XCTAssertEqual(speech.sampleRate, 24_000)
        XCTAssertEqual(speech.samples.count, 3)
        XCTAssertEqual(speech.samples[1], 0.25, accuracy: 0.001)
    }

    func testDecodeRejectsNonWAV() {
        XCTAssertThrowsError(try CloudTTSAudioDecoder.wav(Data(repeating: 0, count: 64)))
    }

    // MARK: - adapter request shapes

    func testOpenAIRequestShape() throws {
        let req = try OpenAITTSAdapter().makeRequest(
            text: "hi", model: "gpt-4o-mini-tts", voice: "alloy", speed: 0.9, key: "sk-x")
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-x")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(body["voice"] as? String, "alloy")
        XCTAssertEqual(body["input"] as? String, "hi")
        XCTAssertEqual(body["response_format"] as? String, "wav")
        XCTAssertEqual(body["speed"] as? Double, 0.9)
    }

    func testMiMoRequestShapeUsesApiKeyHeaderAndNonStreamingWAV() throws {
        let req = try MiMoTTSAdapter().makeRequest(
            text: "hi", model: "mimo-v2.5-tts", voice: "Chloe", speed: 1, key: "sk-x")
        XCTAssertEqual(req.url?.absoluteString, "https://api.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "api-key"), "sk-x")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual((body["audio"] as? [String: Any])?["voice"] as? String, "Chloe")
        XCTAssertEqual((body["audio"] as? [String: Any])?["format"] as? String, "wav")
        XCTAssertNil(body["stream"])  // non-streaming one-shot
        // Text to speak rides in an `assistant` message per MiMo docs.
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.first?["role"] as? String, "assistant")
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.first?["content"] as? String, "hi")
    }

    func testMiniMaxRequestShapeUsesOfficialT2AEndpoint() throws {
        let req = try MiniMaxTTSAdapter().makeRequest(
            text: "今天是不是很开心呀(laughs)，当然了！",
            model: "speech-2.8-hd",
            voice: "male-qn-qingse",
            speed: 1.2,
            key: "mmx-key")

        XCTAssertEqual(req.url?.absoluteString, "https://api.minimaxi.com/v1/t2a_v2")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer mmx-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "speech-2.8-hd")
        XCTAssertEqual(body["text"] as? String, "今天是不是很开心呀(laughs)，当然了！")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["subtitle_enable"] as? Bool, false)
        let voice = body["voice_setting"] as! [String: Any]
        XCTAssertEqual(voice["voice_id"] as? String, "male-qn-qingse")
        XCTAssertEqual(voice["speed"] as? Double, 1.2)
        XCTAssertEqual(voice["vol"] as? Int, 1)
        XCTAssertEqual(voice["pitch"] as? Int, 0)
        let audio = body["audio_setting"] as! [String: Any]
        XCTAssertEqual(audio["sample_rate"] as? Int, 32_000)
        XCTAssertEqual(audio["bitrate"] as? Int, 128_000)
        XCTAssertEqual(audio["format"] as? String, "wav")
        XCTAssertEqual(audio["channel"] as? Int, 1)
    }

    func testMiniMaxRequestAcceptsFullEndpointOverrideWithoutDuplicatingPath() throws {
        var adapter = MiniMaxTTSAdapter()
        adapter.baseURL = URL(string: "https://api.minimaxi.com/v1/t2a_v2")!
        let req = try adapter.makeRequest(
            text: "hi", model: "speech-2.8-hd", voice: "male-qn-qingse", speed: 1, key: "mmx-key")
        XCTAssertEqual(req.url?.absoluteString, "https://api.minimaxi.com/v1/t2a_v2")
    }

    func testVolcengineRequestShapeUsesOfficialV3ChunkedEndpoint() throws {
        let req = try VolcengineTTSAdapter().makeRequest(
            text: "hello",
            model: "seed-tts-2.0",
            voice: "en_male_tim_uranus_bigtts",
            speed: 1.25,
            key: "volc-key")

        XCTAssertEqual(req.url?.absoluteString, "https://openspeech.bytedance.com/api/v3/tts/unidirectional")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Api-Key"), "volc-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Api-Resource-Id"), "seed-tts-2.0")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-Api-Request-Id"))
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let user = body["user"] as! [String: Any]
        XCTAssertEqual(user["uid"] as? String, "responsay-macos")
        let params = body["req_params"] as! [String: Any]
        XCTAssertEqual(params["text"] as? String, "hello")
        XCTAssertEqual(params["speaker"] as? String, "en_male_tim_uranus_bigtts")
        let audio = params["audio_params"] as! [String: Any]
        XCTAssertEqual(audio["format"] as? String, "pcm")
        XCTAssertEqual(audio["sample_rate"] as? Int, 24_000)
        XCTAssertEqual(audio["speech_rate"] as? Int, 25)
    }

    func testGeminiRequestShapeUsesGoogleHeader() throws {
        let req = try GeminiTTSAdapter().makeRequest(
            text: "hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore", speed: 1, key: "AIza-x")
        XCTAssertTrue(req.url!.absoluteString.hasSuffix("/models/gemini-3.1-flash-tts-preview:generateContent"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-x")
    }

    // MARK: - decode of provider JSON envelopes

    func testMiMoDecodeFromNonStreamingWAVEnvelope() throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["audio": ["data": makeWAV([0, 1]).base64EncodedString()]]]],
        ])
        let speech = try MiMoTTSAdapter().decode(json)
        XCTAssertEqual(speech.samples.count, 2)
    }

    func testMiniMaxDecodeFromHexEncodedWAVEnvelope() throws {
        let wav = makeWAV([0, 0.5, -0.5], sampleRate: 32_000)
        let json = try JSONSerialization.data(withJSONObject: [
            "data": ["audio": hex(wav), "status": 2],
            "base_resp": ["status_code": 0, "status_msg": "success"],
        ])

        let speech = try MiniMaxTTSAdapter().decode(json)

        XCTAssertEqual(speech.sampleRate, 32_000)
        XCTAssertEqual(speech.samples.count, 3)
        XCTAssertEqual(speech.samples[1], 0.5, accuracy: 0.001)
    }

    func testVolcengineDecodeCollectsChunkedPCMAndIgnoresFinishEvent() throws {
        let first = pcm16Base64([0, 0.5])
        let second = pcm16Base64([-0.25])
        let body = """
        {"code":0,"message":"","data":"\(first)"}
        {"code":0,"message":"","data":"\(second)"}
        {"code":20000000,"message":"ok","data":null}
        """

        let speech = try VolcengineTTSAdapter().decode(Data(body.utf8))

        XCTAssertEqual(speech.sampleRate, 24_000)
        XCTAssertEqual(speech.samples.count, 3)
        XCTAssertEqual(speech.samples[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(speech.samples[2], -0.25, accuracy: 0.001)
    }

    // MARK: - engine round-trip via stub transport

    func testEngineDecodesStubbedWAVResponse() async throws {
        StubURLProtocol.handler = { _ in (200, self.makeWAV([0, 0.5, -0.5])) }
        let engine = DirectCloudTTSEngine(
            adapter: OpenAITTSAdapter(), model: "gpt-4o-mini-tts", voice: "alloy",
            key: "sk-x", session: StubURLProtocol.session())
        let speech = try await engine.synthesize("hello", speed: 1.0)
        XCTAssertEqual(speech.samples.count, 3)
    }

    func testEngineDecodesStubbedMiMoWAVResponse() async throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["audio": ["data": self.makeWAV([0, 0.5, -0.5]).base64EncodedString()]]]],
        ])
        StubURLProtocol.handler = { _ in (200, json) }
        let engine = DirectCloudTTSEngine(
            adapter: MiMoTTSAdapter(), model: "mimo-v2.5-tts", voice: "Chloe",
            key: "sk-x", session: StubURLProtocol.session())
        let speech = try await engine.synthesize("hello", speed: 1.0)
        XCTAssertEqual(speech.samples.count, 3)
    }

    func testEngineMapsHTTPErrorToTypedError() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":{"message":"bad key"}}"#.utf8)) }
        let engine = DirectCloudTTSEngine(
            adapter: OpenAITTSAdapter(), model: "m", voice: "v", key: "x",
            session: StubURLProtocol.session())
        do {
            _ = try await engine.synthesize("hello", speed: 1.0)
            XCTFail("expected failure")
        } catch let error as TTSError {
            guard case .http(let status) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(error.userMessage.contains("401"))
        } catch { XCTFail("unexpected \(error)") }
    }

    func testEngineEmptyTextThrows() async {
        let engine = DirectCloudTTSEngine(
            adapter: OpenAITTSAdapter(), model: "m", voice: "v", key: "x",
            session: StubURLProtocol.session())
        do { _ = try await engine.synthesize("  ", speed: 1); XCTFail() }
        catch { XCTAssertEqual(error as? TTSError, .emptyText) }
    }

    func testTTSEngineUsesTTSSettingsConfigForDirectRequest() async throws {
        let suite = "test.ttsEngineSettingsConfig"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("openai", forKey: "byok.tts.provider")
        defaults.set("https://tts-proxy.example/v1", forKey: "byok.tts.openai.baseURL")
        defaults.set("tts-model-from-settings", forKey: "byok.tts.openai.model")
        defaults.set("nova", forKey: "byok.tts.openai.voice")

        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.handler = { _ in (200, self.makeWAV([0, 0.5, -0.5])) }
        let synth = try TTSEngine.cloudOpenAI.makeSynthesizer(
            defaults: defaults,
            session: StubURLProtocol.session(),
            keyReader: { account in
                if account == TTSCredential.keychainAccount(for: "openai") { return "tts-secret" }
                if account == TTSCredential.coachAccount(for: "openai") { return "shared-secret" }
                return nil
            })

        _ = try await synth.synthesize("hello", speed: 0.8)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://tts-proxy.example/v1/audio/speech")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tts-secret")
        let bodyData = try XCTUnwrap(StubURLProtocol.lastRequestBody)
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "tts-model-from-settings")
        XCTAssertEqual(body["voice"] as? String, "nova")
        XCTAssertEqual(body["input"] as? String, "hello")
        XCTAssertEqual(body["speed"] as? Double, 0.8)
    }

    func testTTSEngineDoesNotUseSharedKeyWhenTTSProviderConfigured() throws {
        let suite = "test.ttsEngineNoSharedFallback"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("openai", forKey: "byok.tts.provider")

        XCTAssertThrowsError(
            try TTSEngine.cloudOpenAI.makeSynthesizer(
                defaults: defaults,
                session: StubURLProtocol.session(),
                keyReader: { account in
                    account == TTSCredential.coachAccount(for: "openai") ? "shared-secret" : nil
                })
        ) { error in
            XCTAssertEqual(error as? TTSError, .missingAPIKey(provider: "OpenAI"))
        }
    }

    func testTTSEngineDoesNotUseSharedKeyWhenTTSProviderPointerIsUnset() throws {
        let suite = "test.ttsEngineNoLegacySharedFallback"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertThrowsError(
            try TTSEngine.cloudOpenAI.makeSynthesizer(
                defaults: defaults,
                session: StubURLProtocol.session(),
                keyReader: { account in
                    account == TTSCredential.coachAccount(for: "openai") ? "shared-secret" : nil
                })
        ) { error in
            XCTAssertEqual(error as? TTSError, .missingAPIKey(provider: "OpenAI"))
        }
    }

    func testTTSEngineUsesMiniMaxTTSSettingsConfigForDirectRequest() async throws {
        let suite = "test.ttsEngineMiniMaxSettingsConfig"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("minimax", forKey: "byok.tts.provider")
        defaults.set("https://api.minimaxi.com/v1", forKey: "byok.tts.minimax.baseURL")
        defaults.set("speech-2.8-turbo", forKey: "byok.tts.minimax.model")
        // 音色取「可选」菜单里真实提供的一项：selectedVoiceID 会拿 catalog.voices 校验用户的选择,
        // 菜单有而 catalog 没有的音色会被静默丢回默认音色。
        defaults.set("female-yujie", forKey: "byok.tts.minimax.voice")

        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.handler = { _ in
            let json = try! JSONSerialization.data(withJSONObject: [
                "data": ["audio": self.hex(self.makeWAV([0, 0.5], sampleRate: 32_000)), "status": 2],
            ])
            return (200, json)
        }
        let synth = try TTSEngine.cloudMiniMax.makeSynthesizer(
            defaults: defaults,
            session: StubURLProtocol.session(),
            keyReader: { account in
                account == TTSCredential.keychainAccount(for: "minimax") ? "minimax-tts-key" : nil
            })

        _ = try await synth.synthesize("hello", speed: 0.8)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.minimaxi.com/v1/t2a_v2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer minimax-tts-key")
        let bodyData = try XCTUnwrap(StubURLProtocol.lastRequestBody)
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "speech-2.8-turbo")
        XCTAssertEqual(body["text"] as? String, "hello")
        XCTAssertEqual((body["voice_setting"] as? [String: Any])?["voice_id"] as? String,
                       "female-yujie")
        XCTAssertEqual((body["voice_setting"] as? [String: Any])?["speed"] as? Double, 0.8)
    }

    func testVolcengineDirectSynthesizerUsesTTSSettingsConfig() async throws {
        let suite = "test.ttsEngineVolcengineSettingsConfig"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("volcengine-tts", forKey: "byok.tts.provider")
        defaults.set("https://openspeech.bytedance.com/api/v3", forKey: "byok.tts.volcengine-tts.baseURL")
        defaults.set("seed-tts-2.0", forKey: "byok.tts.volcengine-tts.model")
        defaults.set("en_male_tim_uranus_bigtts", forKey: "byok.tts.volcengine-tts.voice")

        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.handler = { _ in
            let json = """
            {"code":0,"message":"","data":"\(self.pcm16Base64([0, 0.5]))"}
            {"code":20000000,"message":"ok","data":null}
            """
            return (200, Data(json.utf8))
        }
        let synth = try TTSEngine.cloudVolcengine.makeSynthesizer(
            defaults: defaults,
            session: StubURLProtocol.session(),
            keyReader: { account in
                account == TTSCredential.keychainAccount(for: "volcengine-tts") ? "volc-tts-key" : nil
            })

        let speech = try await synth.synthesize("hello", speed: 1.0)

        XCTAssertEqual(speech.samples.count, 2)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://openspeech.bytedance.com/api/v3/tts/unidirectional")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "volc-tts-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "seed-tts-2.0")
    }

    func testGeminiDirectSynthesizerDispatchesToNativeGenerateContent() async throws {
        let suite = "test.ttsEngineGeminiSettingsConfig"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("gemini", forKey: "byok.tts.provider")
        defaults.set("gemini-3.1-flash-tts-preview", forKey: "byok.tts.gemini.model")
        defaults.set("Kore", forKey: "byok.tts.gemini.voice")

        StubURLProtocol.lastRequest = nil
        StubURLProtocol.handler = { _ in
            let json = try! JSONSerialization.data(withJSONObject: [
                "candidates": [["content": ["parts": [["inlineData": ["data": self.pcm16Base64([0, 0.5])]]]]]],
            ])
            return (200, json)
        }
        let synth = try TTSEngine.cloudGemini.makeSynthesizer(
            defaults: defaults,
            session: StubURLProtocol.session(),
            keyReader: { account in
                account == TTSCredential.keychainAccount(for: "gemini") ? "AIza-tts-key" : nil
            })

        let speech = try await synth.synthesize("hello", speed: 1.0)

        XCTAssertEqual(speech.samples.count, 2)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        // Native host + custom :generateContent method — NOT the /v1beta/openai/ surface.
        XCTAssertTrue(request.url!.absoluteString.hasSuffix(
            "/v1beta/models/gemini-3.1-flash-tts-preview:generateContent"),
            "unexpected URL: \(request.url!.absoluteString)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-tts-key")
    }
}

/// Canned-response URLProtocol for headless engine tests (no network).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = Self.bodyData(from: request)
        let (status, data) = Self.handler?(request) ?? (200, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}
