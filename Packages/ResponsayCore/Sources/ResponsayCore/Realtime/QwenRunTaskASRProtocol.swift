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
        languageHint: String? = nil,
        languageHints: [String] = [],
        context: [String] = [],
        heartbeat: Bool = false,
        semanticPunctuationEnabled: Bool = false,
        multiThresholdModeEnabled: Bool = false
    ) -> Data {
        var parameters: [String: Any] = ["format": format, "sample_rate": sampleRate]
        let requestedHints = languageHints.isEmpty ? languageHint.map { [$0] } ?? [] : languageHints
        let hintLimit = model.lowercased().hasPrefix("qwen-audio-3.0") ? 4 : 1
        let normalizedHints = Array(requestedHints.compactMap(QwenASRHotwords.languageHint).prefix(hintLimit))
        if !normalizedHints.isEmpty {
            parameters["language_hints"] = normalizedHints
        }
        let vocabulary = QwenASRHotwords.vocabulary(from: hotwords, model: model)
        if !vocabulary.isEmpty {
            parameters["vocabulary"] = vocabulary
        }
        if heartbeat {
            parameters["heartbeat"] = true
        }
        if semanticPunctuationEnabled {
            parameters["semantic_punctuation_enabled"] = true
        }
        // Semantic segmentation disables VAD segmentation. Normalize at the wire boundary too,
        // so a future caller cannot serialize the two product modes as simultaneously enabled.
        if multiThresholdModeEnabled, !semanticPunctuationEnabled {
            parameters["multi_threshold_mode_enabled"] = true
        }
        let contextMessages = userContextMessages(context)
        let input: [String: Any] = contextMessages.isEmpty ? [:] : ["context": contextMessages]
        return json([
            "header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                "input": input,
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

    /// Refreshes the active task's recognition context without reopening the WebSocket.
    public static func continueTask(taskID: String, context: [String]) -> Data {
        let messages = userContextMessages(context)
        let input: [String: Any] = messages.isEmpty ? [:] : ["context": messages]
        return json([
            "header": ["action": "continue-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["input": input],
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

    /// Official context shape for prior user speech. Responsay deliberately sends no assistant
    /// messages: downstream polished/LLM text must not become ASR history. Keep the five newest
    /// messages and the documented 400-character per-turn maximum.
    private static func userContextMessages(_ context: [String]) -> [[String: Any]] {
        context.compactMap { raw -> String? in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(400))
        }
        .suffix(5)
        .map { text in
            [
                "role": "user",
                "content": [["type": "input_text", "text": text]],
            ]
        }
    }
}
