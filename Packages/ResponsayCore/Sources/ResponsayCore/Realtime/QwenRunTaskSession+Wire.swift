import Foundation

extension QwenRunTaskSession {
    /// DashScope run-task wire details are intentionally hidden behind the session interface.
    enum Wire {
        /// Only task-scoped values cross the attempt boundary. Connection credentials and local
        /// capture metadata remain owned by the outer session.
        struct RunTaskOptions: Sendable {
            var model: String
            var hotwords: [String]
            var precompiledVocabularyID: String?
            var languageHints: [String]
            var context: [String]
            var heartbeat: Bool

            init(config: QwenRunTaskCaptureConfig) {
                model = config.model
                hotwords = config.hotwords
                precompiledVocabularyID = config.precompiledVocabularyID
                languageHints = QwenASRHotwords.languageHints(
                    for: config.captureLocale ?? .automatic,
                    model: config.model)
                context = config.context
                heartbeat = config.heartbeat
            }
        }

        enum ServerEvent: Equatable, Sendable {
            case started
            case sentence(id: Int, text: String, isFinal: Bool)
            case finished
            case failure(String)
            case ignored
        }

        static func runTask(
            taskID: String,
            options: RunTaskOptions
        ) -> String {
            var parameters: [String: Any] = ["format": "pcm", "sample_rate": 16_000]
            let hintLimit = options.model.lowercased().hasPrefix("qwen-audio-3.0") ? 4 : 1
            let normalizedHints = Array(
                options.languageHints.compactMap(QwenASRHotwords.languageHint).prefix(hintLimit))
            if !normalizedHints.isEmpty {
                parameters["language_hints"] = normalizedHints
            }
            let vocabulary = QwenASRHotwords.vocabulary(
                from: options.hotwords,
                model: options.model)
            if !vocabulary.isEmpty {
                parameters["vocabulary"] = vocabulary
            } else if QwenASRHotwords.supportsPrecompiledVocabulary(model: options.model),
                      let identifier = QwenASRHotwords.normalizedVocabularyIdentifier(
                        options.precompiledVocabularyID) {
                parameters["vocabulary_id"] = identifier
            }
            if options.heartbeat {
                parameters["heartbeat"] = true
            }
            let messages = userContextMessages(options.context)
            let input: [String: Any] = messages.isEmpty ? [:] : ["context": messages]
            return json([
                "header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
                "payload": [
                    "task_group": "audio",
                    "task": "asr",
                    "function": "recognition",
                    "model": options.model,
                    "parameters": parameters,
                    "input": input,
                ],
            ])
        }

        static func finishTask(taskID: String) -> String {
            json([
                "header": ["action": "finish-task", "task_id": taskID, "streaming": "duplex"],
                "payload": ["input": [:] as [String: Any]],
            ])
        }

        static func continueTask(taskID: String, context: [String]) -> String {
            let messages = userContextMessages(context)
            let input: [String: Any] = messages.isEmpty ? [:] : ["context": messages]
            return json([
                "header": ["action": "continue-task", "task_id": taskID, "streaming": "duplex"],
                "payload": ["input": input],
            ])
        }

        static func decode(_ message: QwenRunTaskTransportMessage) -> ServerEvent {
            switch message {
            case let .text(text):
                return decode(Data(text.utf8))
            case let .data(data):
                return decode(data)
            }
        }

        private static func decode(_ data: Data) -> ServerEvent {
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
                if sentence["heartbeat"] as? Bool == true { return .ignored }
                return .sentence(
                    id: sentence["sentence_id"] as? Int ?? 0,
                    text: sentence["text"] as? String ?? "",
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

        private static func json(_ object: [String: Any]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }

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
}
