import Foundation

enum MiMoASRStreamEvent: Equatable {
    case delta(String)
    case done
    case failure(String)
    case ignored
}

enum MiMoASRStreamDecoder {
    static func eventData(from line: String) -> Data? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        if trimmed.hasPrefix("data:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return payload.isEmpty ? nil : Data(payload.utf8)
        }
        if trimmed == "[DONE]" || trimmed.hasPrefix("{") {
            return Data(trimmed.utf8)
        }
        return nil
    }

    static func decode(_ eventData: Data) -> MiMoASRStreamEvent {
        if String(data: eventData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return .done
        }
        guard let obj = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            return .ignored
        }
        if let message = errorMessage(in: obj) {
            return .failure(message)
        }
        guard let choices = obj["choices"] as? [[String: Any]] else { return .ignored }
        var sawFinish = false
        for choice in choices {
            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String,
               !content.isEmpty {
                return .delta(content)
            }
            if choice["finish_reason"] is String { sawFinish = true }
        }
        return sawFinish ? .done : .ignored
    }

    private static func errorMessage(in obj: [String: Any]) -> String? {
        if let error = obj["error"] as? String { return error }
        if let error = obj["error"] as? [String: Any] {
            return error["message"] as? String ?? "MiMo ASR 流式响应错误"
        }
        return nil
    }
}
