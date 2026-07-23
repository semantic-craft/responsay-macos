import Foundation
import Testing
@testable import ResponsayCore

/// Pins the qwen3-asr-flash-realtime OmniRealtime protocol (help.aliyun.com
/// real-time-speech-recognition-user-guide): Manual turn mode (`turn_detection: null`)
/// for push-to-talk, `input_audio_buffer.append/commit`, and the transcription events
/// (`...text` = live text+stash → preview; `...completed` = transcript → final).
@Suite("Qwen realtime ASR protocol")
struct QwenRealtimeASRProtocolTests {
    typealias P = QwenRealtimeASRProtocol

    // MARK: - Client → server payloads

    @Test func sessionUpdateSelectsManualTurnAndFormat() throws {
        let json = try Self.decode(P.sessionUpdate(language: "zh", sampleRate: 16000, format: "pcm"))
        #expect(json["type"] as? String == "session.update")
        let session = try #require(json["session"] as? [String: Any])
        // Manual mode = push-to-talk: server VAD off, client commits on Fn-release.
        #expect(session["turn_detection"] is NSNull)
        #expect(session["input_audio_format"] as? String == "pcm")
    }

    @Test func appendAudioBase64EncodesPCM() throws {
        let pcm = Data([0x00, 0x01, 0x02, 0x03])
        let json = try Self.decode(P.appendAudio(pcm))
        #expect(json["type"] as? String == "input_audio_buffer.append")
        #expect(json["audio"] as? String == pcm.base64EncodedString())
    }

    @Test func commitEndsTheTurn() throws {
        let json = try Self.decode(P.commit())
        #expect(json["type"] as? String == "input_audio_buffer.commit")
    }

    // MARK: - Server → client events

    @Test func decodesLivePartialAsTextPlusStash() throws {
        let frame = Data(#"{"type":"conversation.item.input_audio_transcription.text","text":"你好","stash":"世"}"#.utf8)
        #expect(P.decode(frame) == .partial(text: "你好", stash: "世"))
    }

    @Test func decodesCompletedAsFinalTranscript() throws {
        let frame = Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好世界"}"#.utf8)
        #expect(P.decode(frame) == .completed(transcript: "你好世界"))
    }

    @Test func decodesErrorEvent() throws {
        let frame = Data(#"{"type":"error","error":{"message":"bad key"}}"#.utf8)
        #expect(P.decode(frame) == .failure("bad key"))
    }

    @Test func ignoresUnrelatedEvents() throws {
        #expect(P.decode(Data(#"{"type":"session.created","session":{"id":"x"}}"#.utf8)) == .ignored)
        #expect(P.decode(Data(#"{"type":"input_audio_buffer.speech_started"}"#.utf8)) == .ignored)
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
