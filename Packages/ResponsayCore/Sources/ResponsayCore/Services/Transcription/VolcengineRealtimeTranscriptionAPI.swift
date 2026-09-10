import Foundation

/// Live PCM upload over the whole-utterance `bigmodel_nostream` endpoint.
/// Intermediate cumulative responses are drained but never exposed to insertion.
public struct VolcengineRealtimeTranscriptionAPI: Sendable {
    let endpoint: VolcengineRealtimeEndpoint
    let config: VolcengineRealtimeConfig
    let hotwordsProvider: @Sendable () async -> [String]
    var transportProvider: @Sendable (URLRequest) -> any VolcengineRealtimeTransport
    /// 200 ms of 16 kHz mono Int16 PCM, as recommended by the provider.
    let frameBytes: Int

    public init(
        endpoint: VolcengineRealtimeEndpoint,
        config: VolcengineRealtimeConfig = VolcengineRealtimeConfig(),
        hotwordsProvider: (@Sendable () async -> [String])? = nil,
        session: URLSession = .shared,
        webSocketTaskProvider: (@Sendable (URLRequest) -> URLSessionWebSocketTask)? = nil,
        frameBytes: Int = 6_400
    ) {
        self.endpoint = endpoint
        self.config = config
        self.hotwordsProvider = hotwordsProvider ?? { config.hotwords }
        let makeTask = webSocketTaskProvider ?? { session.webSocketTask(with: $0) }
        self.transportProvider = { VolcengineURLSessionTransport(task: makeTask($0)) }
        self.frameBytes = max(2, frameBytes)
    }

    public func transcribe(audio: AsyncStream<Data>) async throws -> String {
        guard !endpoint.apiKey.isEmpty else {
            throw CoachAPIError.message("未配置火山引擎 API Key。请在设置中配置。")
        }
        let requestConfig = await resolvedRequestConfig()
        try Task.checkCancellation()
        let socket = transportProvider(endpoint.makeRequest(connectID: UUID().uuidString))
        socket.start()
        defer { socket.cancel() }
        let client = VolcengineRealtimeClient(transport: socket)
        return try await withTaskCancellationHandler {
            try await client.sendFullClientRequest(config: requestConfig)
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    var pending = Data()
                    for await chunk in audio {
                        try Task.checkCancellation()
                        pending.append(chunk)
                        while pending.count >= frameBytes {
                            try await client.sendAudio(Data(pending.prefix(frameBytes)))
                            pending.removeFirst(frameBytes)
                        }
                    }
                    try Task.checkCancellation()
                    if !pending.isEmpty { try await client.sendAudio(pending) }
                    try await client.sendFinish()
                    return nil
                }
                group.addTask { try await Self.drainFinal(from: client) }
                defer { group.cancelAll() }
                do {
                    while let result = try await group.next() {
                        if let result { return result }
                    }
                    throw CoachAPIError.message("豆包未返回最终识别结果。")
                } catch {
                    socket.cancel()
                    if Task.isCancelled { throw CancellationError() }
                    throw error
                }
            }
        } onCancel: {
            socket.cancel()
        }
    }

    /// Resolves the one immutable full-client-request payload at transcription time. Capture can
    /// finish harvesting screen terms while audio is recorded, without rebuilding the endpoint or
    /// reading mutable settings after this point.
    func resolvedRequestConfig() async -> VolcengineRealtimeConfig {
        var requestConfig = config
        requestConfig.hotwords = await hotwordsProvider()
        return requestConfig
    }

    /// Read server frames until the terminal (`isLast`) transcript arrives.
    private static func drainFinal(from client: VolcengineRealtimeClient) async throws -> String {
        while true {
            let message = try await client.receive()
            switch await client.handleEvent(message) {
            case .final(let text):
                return text
            case .failed(let reason):
                throw CoachAPIError.message(reason ?? "火山引擎流式识别失败")
            case .partial, .none:
                continue
            }
        }
    }

}
