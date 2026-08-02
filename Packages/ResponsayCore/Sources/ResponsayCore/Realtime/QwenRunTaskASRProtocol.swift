import Foundation

/// Codec for 百炼 实时语音识别 over DashScope's **run-task** WebSocket protocol
/// (`/api-ws/v1/inference`) — the protocol Qwen-Audio-3.0-ASR-Flash-Streaming and
/// Fun-ASR-Realtime speak. Distinct from the OmniRealtime/OpenAI-Realtime protocol at the sibling
/// `/api-ws/v1/realtime` path, which only qwen3-asr-flash-realtime speaks and which supports no
/// hotwords at all.
///
/// Documented flow: connect → `run-task` → wait for `task-started` → binary mono PCM frames →
/// `result-generated` events → `finish-task` → trailing `result-generated` → `task-finished`.
/// **Audio must not be sent before `task-started` arrives.**
///
/// Turn shape for push-to-talk: this protocol has no client-side commit, only server VAD plus
/// `finish-task`. Holding the hotkey streams frames; releasing sends `finish-task`, which makes the
/// server flush the trailing sentence as final. Sentences are then joined into one 整段 transcript.
///
/// Pure/synchronous so payloads + event parsing are unit-tested without a socket.
public enum QwenRunTaskASRProtocol {
    public enum ServerEvent: Equatable, Sendable {
        /// Task accepted — audio frames may start.
        case started
        /// One recognition result. `isFinal` mirrors `sentence_end`; heartbeat frames are
        /// swallowed as `.ignored` since the docs say to skip them.
        case sentence(id: Int, text: String, isFinal: Bool)
        case finished
        case failure(String)
        case ignored
    }

    // MARK: - Client → server

    public static func runTask(
        taskID: String,
        model: String,
        sampleRate: Int = 16_000,
        format: String = "pcm",
        hotwords: [String] = [],
        languageHint: String? = nil
    ) -> Data {
        var parameters: [String: Any] = ["format": format, "sample_rate": sampleRate]
        if let languageHint {
            // Qwen-Audio-3.0-ASR-Flash-Streaming honours up to 4 hints, Fun-ASR-Realtime only the
            // first; one hint matches the locale the user explicitly picked and is valid for both.
            parameters["language_hints"] = [languageHint]
        }
        let vocabulary = QwenASRHotwords.vocabulary(from: hotwords, model: model)
        if !vocabulary.isEmpty {
            parameters["vocabulary"] = vocabulary
        }
        return json([
            "header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                // `input` is required; `{}` means "no 上下文增强". The 词典 already rides
                // `vocabulary`, and context works by the same 词表匹配 mechanism, so sending both
                // would be redundant — and free text risks the model echoing the list back.
                "input": [:] as [String: Any],
            ],
        ])
    }

    /// All audio sent — ask the server to flush the trailing sentence and end the task.
    public static func finishTask(taskID: String) -> Data {
        json([
            "header": ["action": "finish-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["input": [:] as [String: Any]],
        ])
    }

    // MARK: - Server → client

    public static func decode(_ data: Data) -> ServerEvent {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = root["header"] as? [String: Any],
              let event = header["event"] as? String else {
            return .ignored
        }
        switch event {
        case "task-started":
            return .started
        case "result-generated":
            guard let payload = root["payload"] as? [String: Any],
                  let output = payload["output"] as? [String: Any],
                  let sentence = output["sentence"] as? [String: Any] else {
                return .ignored
            }
            // Heartbeats keep an idle socket alive and carry no transcript (sentence_id is
            // pinned to 0); the docs say to skip them.
            if sentence["heartbeat"] as? Bool == true { return .ignored }
            let text = sentence["text"] as? String ?? ""
            return .sentence(
                id: sentence["sentence_id"] as? Int ?? 0,
                text: text,
                isFinal: sentence["sentence_end"] as? Bool ?? false)
        case "task-finished":
            return .finished
        case "task-failed":
            let code = header["error_code"] as? String ?? ""
            let message = header["error_message"] as? String ?? ""
            let detail = [code, message].filter { !$0.isEmpty }.joined(separator: ": ")
            return .failure(detail.isEmpty ? "千问实时识别失败" : detail)
        default:
            return .ignored
        }
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
