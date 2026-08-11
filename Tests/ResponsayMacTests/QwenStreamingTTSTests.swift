import XCTest
@testable import ResponsayMac
import ResponsayCore
@testable import ResponsaySpeech

/// Qwen-Audio-TTS 3.0 Flash: native DashScope task events + binary PCM frames.
final class QwenStreamingTTSTests: XCTestCase {
    private let taskID = UUID(uuidString: "2bf83b9a-baeb-4fda-8d9a-111111111111")!

    private func pcm16(_ samples: [Float]) -> Data {
        Data(base64Encoded: TTSTestAudio.pcm16Base64(samples))!
    }

    private func frame(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func event(_ name: String, extra: [String: Any] = [:]) -> Data {
        var header: [String: Any] = ["event": name]
        for (key, value) in extra { header[key] = value }
        return frame(["header": header, "payload": [:]])
    }

    private func framesStream(_ frames: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }

    func testDecodeNativeEventsAndBinaryAudio() {
        XCTAssertEqual(QwenAudioTTSProtocol.decode(event("task-started")), .started)
        XCTAssertEqual(QwenAudioTTSProtocol.decode(event("task-finished")), .done)
        XCTAssertEqual(
            QwenAudioTTSProtocol.decode(event("task-failed", extra: ["error_message": "bad voice"])),
            .failure("bad voice"))
        XCTAssertEqual(QwenAudioTTSProtocol.decode(event("result-generated")), .ignored)

        let audio = pcm16([0, 0.5])
        XCTAssertEqual(QwenAudioTTSProtocol.decode(audio), .audio(audio))
    }

    func testRunTaskUsesOfficialQwenAudioShape() throws {
        let data = QwenAudioTTSProtocol.runTask(
            taskID: taskID,
            model: "qwen-audio-3.0-tts-flash",
            voice: "loongeva_v3.6",
            speed: 3,
            instruction: "Speak warmly.")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let header = try XCTUnwrap(object["header"] as? [String: Any])
        XCTAssertEqual(header["action"] as? String, "run-task")
        XCTAssertEqual(header["task_id"] as? String, taskID.uuidString.lowercased())
        XCTAssertEqual(header["streaming"] as? String, "duplex")

        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["task_group"] as? String, "audio")
        XCTAssertEqual(payload["task"] as? String, "tts")
        XCTAssertEqual(payload["function"] as? String, "SpeechSynthesizer")
        XCTAssertEqual(payload["model"] as? String, "qwen-audio-3.0-tts-flash")
        let parameters = try XCTUnwrap(payload["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["voice"] as? String, "loongeva_v3.6")
        XCTAssertEqual(parameters["format"] as? String, "pcm")
        XCTAssertEqual(parameters["sample_rate"] as? Int, 24_000)
        XCTAssertEqual(parameters["rate"] as? Double, 2)
        XCTAssertEqual(parameters["instruction"] as? String, "Speak warmly.")
    }

    func testContinueAndFinishReuseTaskID() throws {
        let continueObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: QwenAudioTTSProtocol.continueTask(taskID: taskID, text: "Hello")) as? [String: Any])
        let continueHeader = try XCTUnwrap(continueObject["header"] as? [String: Any])
        let continuePayload = try XCTUnwrap(continueObject["payload"] as? [String: Any])
        XCTAssertEqual(continueHeader["action"] as? String, "continue-task")
        XCTAssertEqual(continueHeader["task_id"] as? String, taskID.uuidString.lowercased())
        XCTAssertEqual((continuePayload["input"] as? [String: Any])?["text"] as? String, "Hello")

        let finishObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: QwenAudioTTSProtocol.finishTask(taskID: taskID)) as? [String: Any])
        let finishHeader = try XCTUnwrap(finishObject["header"] as? [String: Any])
        XCTAssertEqual(finishHeader["action"] as? String, "finish-task")
        XCTAssertEqual(finishHeader["task_id"] as? String, taskID.uuidString.lowercased())
    }

    func testEndpointUsesInferencePathWithoutModelQuery() {
        XCTAssertEqual(
            QwenAudioTTSEndpoint(region: .china).url.absoluteString,
            "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(
            QwenAudioTTSEndpoint(region: .singapore).url.absoluteString,
            "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference")
    }

    func testChunksAssembleBinaryPCMThenStop() async throws {
        let frames = framesStream([
            event("task-started"),
            pcm16([0, 0.5]),
            event("result-generated"),
            pcm16([0.25, -0.25, 0.1]),
            event("task-finished"),
            pcm16([1]),
        ])
        var chunks: [SynthesizedSpeech] = []
        for try await chunk in QwenStreamingTTSEngine.chunks(from: frames) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].samples.count, 2)
        XCTAssertEqual(chunks[1].samples.count, 3)
        XCTAssertEqual(chunks[0].sampleRate, 24_000)
    }

    func testChunksThrowOnTaskFailure() async {
        let frames = framesStream([
            pcm16([0]),
            event("task-failed", extra: ["error_message": "quota"]),
        ])
        do {
            for try await _ in QwenStreamingTTSEngine.chunks(from: frames) {}
            XCTFail("expected throw")
        } catch let error as TTSError {
            XCTAssertEqual(error, .synthesisFailed("quota"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testQwenFactoriesUseSingleCurrentModelAndDefaultVoice() throws {
        let suite = "test.qwenAudioTTSDefault"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let keyReader: (String) -> String? = { account in
            account == TTSCredential.keychainAccount(for: "qwen") ? "tts-secret" : nil
        }
        let streaming = try TTSEngine.cloudQwen.makeStreamingSynthesizer(
            defaults: defaults,
            keyReader: keyReader)
        let collected = try TTSEngine.cloudQwen.makeSynthesizer(
            defaults: defaults,
            keyReader: keyReader)

        for engine in [
            try XCTUnwrap(streaming as? QwenStreamingTTSEngine),
            try XCTUnwrap(collected as? QwenStreamingTTSEngine),
        ] {
            XCTAssertEqual(engine.model, "qwen-audio-3.0-tts-flash")
            XCTAssertEqual(engine.voice, "loongeva_v3.6")
            XCTAssertEqual(engine.key, "tts-secret")
        }
    }

    func testQwenFactoryUsesValidVoiceAndSingaporeRegionButIgnoresOldModel() throws {
        let suite = "test.qwenAudioTTSSettings"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("qwen3-tts-flash-realtime", forKey: "byok.tts.model")
        defaults.set("loongjohn", forKey: "byok.tts.voice")
        defaults.set(ProviderRegion.singapore.rawValue, forKey: "byok.tts.region")

        let synth = try TTSEngine.cloudQwen.makeStreamingSynthesizer(
            defaults: defaults,
            keyReader: { account in
                account == TTSCredential.keychainAccount(for: "qwen") ? "tts-secret" : nil
            })
        let engine = try XCTUnwrap(synth as? QwenStreamingTTSEngine)
        XCTAssertEqual(engine.model, "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(engine.voice, "loongjohn")
        XCTAssertEqual(engine.region, .singapore)
    }

    func testQwenFactoryRejectsRetiredVoiceByFallingBackToCurrentDefault() throws {
        let suite = "test.qwenAudioTTSRetiredVoice"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("Cherry", forKey: "byok.tts.voice")

        let synth = try TTSEngine.cloudQwen.makeStreamingSynthesizer(
            defaults: defaults,
            keyReader: { _ in "tts-secret" })
        let engine = try XCTUnwrap(synth as? QwenStreamingTTSEngine)
        XCTAssertEqual(engine.voice, "loongeva_v3.6")
    }

    func testNonQwenEnginesDoNotExposeStreaming() throws {
        XCTAssertNil(try TTSEngine.cloudOpenAI.makeStreamingSynthesizer())
        XCTAssertNil(try TTSEngine.sherpaKokoroLocal.makeStreamingSynthesizer())
    }
}
