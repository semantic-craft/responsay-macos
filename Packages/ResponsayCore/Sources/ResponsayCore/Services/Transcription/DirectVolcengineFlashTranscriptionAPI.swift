import Foundation

/// App-direct (BYOK) ASR via Volcengine **大模型录音文件识别 标准版 2.0** (`volc.seedasr.auc`).
///
/// Two-stage async flow (docs 6561/1354868): POST `/auc/bigmodel/submit` with the clip inline
/// (base64 `audio.data`), then poll `/auc/bigmodel/query` with the same `X-Api-Request-Id`
/// (the task id) until `X-Api-Status-Code` reports done. New-console auth (`X-Api-Key`).
///
/// (The `Flash`/`volcengine-flash` names are legacy ids kept to avoid a settings/keychain
/// migration; the path is the standard 2.0 submit/query, not the 极速版 flash — 极速版
/// `auc_turbo` requires a separate grant that the new-console key's account面 lacked.)
public struct DirectVolcengineFlashTranscriptionAPI: TranscriptionAPI {
    private static let resourceID = "volc.seedasr.auc"
    private static let brand = "火山引擎录音识别"
    private static let successCode = "20000000"
    private static let processingCodes: Set<String> = ["20000001", "20000002"]  // 处理中 / 队列中
    private static let silentCode = "20000003"                                   // 静音音频

    private let baseURL: URL
    private let session: URLSession
    private let maxAudioBytes: Int
    private let modelProvider: @Sendable () -> String
    private let apiKeyProvider: @Sendable () -> String
    private let requestIDProvider: @Sendable () -> String
    private let pollInterval: TimeInterval
    private let maxPolls: Int

    public init(
        baseURL: URL = URL(string: "https://openspeech.bytedance.com/api/v3")!,
        session: URLSession = .shared,
        // The standard API caps a single submitted file at 512 MB; base64 inline keeps the app's
        // short dictation clips well under that. 20 MB matches the other direct clients.
        maxAudioBytes: Int = 20_000_000,
        modelProvider: @escaping @Sendable () -> String = { "bigmodel" },
        apiKeyProvider: @escaping @Sendable () -> String = { "" },
        requestIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        pollInterval: TimeInterval = 1.0,
        maxPolls: Int = 120
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAudioBytes = maxAudioBytes
        self.modelProvider = modelProvider
        self.apiKeyProvider = apiKeyProvider
        self.requestIDProvider = requestIDProvider
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        try ASRHTTPGuards.audioSize(audio, max: maxAudioBytes)
        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置火山引擎 API Key。请在设置中配置。")
        }
        let model = modelProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? "bigmodel" : model
        let taskID = requestID()

        try await submit(audio: audio, mimeType: mimeType, model: resolvedModel, key: key, taskID: taskID)
        let text = try await pollResult(key: key, taskID: taskID)
        try ASRHTTPGuards.nonEmpty(text, brand: Self.brand)
        return TranscriptionResult(text: text, model: resolvedModel, language: "auto", provider: "volcengine-flash")
    }

    // MARK: - Submit

    private func submit(audio: Data, mimeType: String, model: String, key: String, taskID: String) async throws {
        var request = makeRequest(action: "submit", key: key, taskID: taskID)
        request.httpBody = try JSONEncoder().encode(VolcengineSubmitRequest(
            user: .init(uid: taskID),
            audio: .init(data: audio.base64EncodedString(), format: Self.audioFormat(forMime: mimeType)),
            request: .init(modelName: model)))
        let (data, response) = try await session.data(for: request)
        let http = try ASRHTTPGuards.validate(response, data: data, brand: Self.brand)
        let code = Self.header("X-Api-Status-Code", from: http) ?? ""
        guard code == Self.successCode else {
            throw CoachAPIError.message("\(Self.brand) 提交失败 \(code): \(Self.message(http))")
        }
    }

    // MARK: - Query (poll)

    private func pollResult(key: String, taskID: String) async throws -> String {
        for _ in 0..<maxPolls {
            var request = makeRequest(action: "query", key: key, taskID: taskID)
            request.httpBody = Data("{}".utf8)
            let (data, response) = try await session.data(for: request)
            let http = try ASRHTTPGuards.validate(response, data: data, brand: Self.brand)
            let code = Self.header("X-Api-Status-Code", from: http) ?? ""

            if code == Self.successCode {
                let decoded = try JSONDecoder().decode(VolcengineQueryResponse.self, from: data)
                return decoded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if code == Self.silentCode {
                throw CoachAPIError.message("\(Self.brand) 没有检测到人声。")
            }
            guard Self.processingCodes.contains(code) else {
                throw CoachAPIError.message("\(Self.brand) \(code): \(Self.message(http))")
            }
            try await Task.sleep(nanoseconds: UInt64(max(0, pollInterval) * 1_000_000_000))
        }
        throw CoachAPIError.message("\(Self.brand) 识别超时，请重试。")
    }

    // MARK: - Helpers

    private func makeRequest(action: String, key: String, taskID: String) -> URLRequest {
        var request = URLRequest(url: endpoint(action))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(taskID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        request.timeoutInterval = 60
        return request
    }

    /// `<base>/auc/bigmodel/<action>` — appends components individually so the path isn't
    /// double-built when `baseURL` already ends in `/api/v3`.
    private func endpoint(_ action: String) -> URL {
        let trimmed = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("auc/bigmodel/\(action)") { return baseURL }
        return baseURL
            .appendingPathComponent("auc")
            .appendingPathComponent("bigmodel")
            .appendingPathComponent(action)
    }

    /// Map the captured clip's MIME type to Volcengine's `audio.format` (raw / wav / mp3 / ogg).
    /// The app records WAV, so wav is the safe default.
    private static func audioFormat(forMime mime: String) -> String {
        let m = mime.lowercased()
        if m.contains("wav") { return "wav" }
        if m.contains("mp3") || m.contains("mpeg") { return "mp3" }
        if m.contains("ogg") || m.contains("opus") { return "ogg" }
        return "wav"
    }

    private func requestID() -> String {
        let value = requestIDProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? UUID().uuidString : value
    }

    private static func message(_ response: HTTPURLResponse) -> String {
        header("X-Api-Message", from: response) ?? "识别失败"
    }

    private static func header(_ name: String, from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            if String(describing: key).caseInsensitiveCompare(name) == .orderedSame {
                return String(describing: value)
            }
        }
        return nil
    }
}

private struct VolcengineSubmitRequest: Encodable {
    struct User: Encodable { let uid: String }
    struct Audio: Encodable {
        let data: String
        let format: String
    }
    struct RecognitionOptions: Encodable {
        let modelName: String
        private enum CodingKeys: String, CodingKey { case modelName = "model_name" }
    }
    let user: User
    let audio: Audio
    let request: RecognitionOptions
}

private struct VolcengineQueryResponse: Decodable {
    struct Result: Decodable { let text: String? }
    let result: Result?
    var transcript: String { result?.text ?? "" }
}
