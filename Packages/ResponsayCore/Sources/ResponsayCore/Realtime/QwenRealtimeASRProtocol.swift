import Foundation

/// Codec for qwen3-asr-flash-realtime over DashScope's OmniRealtime WebSocket
/// (`/api-ws/v1/realtime`, OpenAI-Realtime-style JSON events). Manual turn mode
/// (`turn_detection: null`) suits push-to-talk: append audio while the hotkey is held,
/// `commit` on release. Pure/synchronous so payloads + event parsing are unit-tested
/// without a socket. (session.update's exact transcription sub-schema is the one bit to
/// confirm on real hardware; append/commit/events are pinned by the official SDK samples.)
public enum QwenRealtimeASRProtocol {
    public enum ServerEvent: Equatable, Sendable {
        /// Live incremental transcript: `text` is settled, `stash` is the volatile tail.
        case partial(text: String, stash: String)
        /// Terminal transcript for the utterance — the source of truth for skills + insertion.
        case completed(transcript: String)
        case failure(String)
        case ignored
    }

    // MARK: - Client → server

    public static func sessionUpdate(language: String, sampleRate: Int, format: String) -> Data {
        let session: [String: Any] = [
            "turn_detection": NSNull(),          // Manual mode: the hotkey defines the turn, not VAD.
            "input_audio_format": format,
            "modalities": ["text"],
            "input_audio_transcription": [
                "language": language,
                "sample_rate": sampleRate,
            ],
        ]
        return json(["type": "session.update", "session": session])
    }

    public static func appendAudio(_ pcm: Data) -> Data {
        json(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    /// End the current turn (Manual mode) → server emits the `...completed` transcript.
    public static func commit() -> Data {
        json(["type": "input_audio_buffer.commit"])
    }

    // MARK: - Server → client

    public static func decode(_ data: Data) -> ServerEvent {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String else {
            return .ignored
        }
        switch type {
        case "conversation.item.input_audio_transcription.text":
            return .partial(text: root["text"] as? String ?? "", stash: root["stash"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .completed(transcript: root["transcript"] as? String ?? "")
        case "error":
            if let error = root["error"] as? [String: Any] {
                return .failure(error["message"] as? String ?? "qwen 实时识别错误")
            }
            return .failure(root["message"] as? String ?? "qwen 实时识别错误")
        default:
            return .ignored
        }
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
