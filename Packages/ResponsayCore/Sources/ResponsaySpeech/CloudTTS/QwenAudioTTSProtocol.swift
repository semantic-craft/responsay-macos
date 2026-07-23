import Foundation

enum QwenAudioTTSProtocol {
    enum Event: Equatable {
        case started
        case audio(Data)
        case done
        case failure(String)
        case ignored
    }

    static func decode(_ frame: Data) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: frame),
              let message = object as? [String: Any] else {
            return frame.isEmpty ? .ignored : .audio(frame)
        }
        guard let header = message["header"] as? [String: Any],
              let event = header["event"] as? String else {
            return .ignored
        }
        switch event {
        case "task-started":
            return .started
        case "task-finished":
            return .done
        case "task-failed":
            let message = header["error_message"] as? String
                ?? header["error_code"] as? String
                ?? "通义千问语音合成失败"
            return .failure(message)
        default:
            return .ignored
        }
    }

    static func runTask(
        taskID: UUID,
        model: String,
        voice: String,
        speed: Double,
        instruction: String?
    ) -> Data {
        var parameters: [String: Any] = [
            "text_type": "PlainText",
            "voice": voice,
            "format": "pcm",
            "sample_rate": 24_000,
            "volume": 50,
            "rate": min(2, max(0.5, speed)),
            "pitch": 1.0,
            "enable_ssml": false,
        ]
        if let instruction, !instruction.isEmpty {
            parameters["instruction"] = instruction
        }
        return json([
            "header": header(action: "run-task", taskID: taskID),
            "payload": [
                "task_group": "audio",
                "task": "tts",
                "function": "SpeechSynthesizer",
                "model": model,
                "parameters": parameters,
                "input": [String: Any](),
            ],
        ])
    }

    static func continueTask(taskID: UUID, text: String) -> Data {
        json([
            "header": header(action: "continue-task", taskID: taskID),
            "payload": ["input": ["text": text]],
        ])
    }

    static func finishTask(taskID: UUID) -> Data {
        json([
            "header": header(action: "finish-task", taskID: taskID),
            "payload": ["input": [String: Any]()],
        ])
    }

    private static func header(action: String, taskID: UUID) -> [String: Any] {
        [
            "action": action,
            "task_id": taskID.uuidString.lowercased(),
            "streaming": "duplex",
        ]
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
