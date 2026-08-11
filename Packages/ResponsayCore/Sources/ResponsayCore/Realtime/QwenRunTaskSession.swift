import Foundation

public enum QwenRunTaskSessionError: Error, LocalizedError, Sendable {
    case connectionBusy
    case taskEndedBeforeStart
    case taskFailed(String?)
    case taskEndedWithoutFinal
    case taskResponseTimedOut

    public var errorDescription: String? {
        switch self {
        case .connectionBusy: "千问实时识别连接仍在处理上一任务。"
        case .taskEndedBeforeStart: "千问实时识别任务未能启动。"
        case let .taskFailed(message): message ?? "千问实时识别失败"
        case .taskEndedWithoutFinal: "千问实时识别未返回最终结果。"
        case .taskResponseTimedOut: "千问实时识别响应超时。"
        }
    }
}

public struct QwenRunTaskStartMetric: Sendable, Equatable {
    public var reusedConnection: Bool
    public var runTaskToStartedNanos: UInt64

    public init(reusedConnection: Bool, runTaskToStartedNanos: UInt64) {
        self.reusedConnection = reusedConnection
        self.runTaskToStartedNanos = runTaskToStartedNanos
    }
}

/// The deep run-task session interface used by live capture. Production uses
/// `QwenRunTaskSession`; routing tests substitute only the remote exchange while keeping the
/// shipped capture adapter and its audio/finalization flow intact.
public protocol QwenRunTaskTranscribing: Sendable {
    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String
}

/// Owns the transport lifetime separately from task lifetime. Official DashScope guidance permits
/// another `run-task` only after `task-finished`, requires a fresh task ID, invalidates the socket
/// after task failure, and closes an idle connection server-side after 60 seconds. We therefore
/// retain only successfully completed sockets and expire them locally after 45 seconds.
public actor QwenRunTaskSession: QwenRunTaskTranscribing {
    typealias TransportFactory = @Sendable (URLRequest) async throws -> any QwenRunTaskTransport
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    private struct ConnectionKey: Equatable, Sendable {
        var url: URL?
        var authorization: String?
        var workspaceID: String?

        init(_ request: URLRequest) {
            url = request.url
            authorization = request.value(forHTTPHeaderField: "Authorization")
            workspaceID = request.value(forHTTPHeaderField: "X-DashScope-WorkSpace")
        }
    }

    private struct Connection: Sendable {
        var id: UUID
        var key: ConnectionKey
        var transport: any QwenRunTaskTransport
        var inUse: Bool
    }

    private struct Lease: Sendable {
        var id: UUID
        var transport: any QwenRunTaskTransport
        var reused: Bool
    }

    private enum AttemptResult: Sendable {
        case senderFinished
        case transcript(String)
    }

    private struct FinalSentenceKey: Hashable {
        var id: Int
        var text: String
    }

    /// One instance belongs to one logical capture and survives its single reconnect attempt.
    private actor TaskCallbackState {
        private var forwardedFinalSentences = Set<FinalSentenceKey>()
        private var latestContext: [String]?

        func shouldForward(id: Int, text: String) -> Bool {
            return forwardedFinalSentences.insert(.init(id: id, text: text)).inserted
        }

        func recordLatestContext(_ context: [String]) {
            latestContext = context
        }

        func contextForNextAttempt(fallback: [String]) -> [String] {
            latestContext ?? fallback
        }
    }

    private var connection: Connection?
    private var idleCloseTask: Task<Void, Never>?
    private var idleGeneration: UUID?
    private let factory: TransportFactory
    private let sleeper: Sleeper
    private let idleTimeoutNanos: UInt64
    private let taskResponseTimeoutNanos: UInt64
    private let taskResponseSleeper: Sleeper
    private let taskIDProvider: @Sendable () -> String
    private let nowNanos: @Sendable () -> UInt64

    public init(
        session: URLSession = .shared,
        idleTimeoutNanos: UInt64 = 45_000_000_000,
        taskResponseTimeoutNanos: UInt64 = 5_000_000_000
    ) {
        self.idleTimeoutNanos = idleTimeoutNanos
        self.taskResponseTimeoutNanos = taskResponseTimeoutNanos
        factory = { request in
            let task = session.webSocketTask(with: request)
            return QwenURLSessionWebSocketTransport(task: task, resume: true)
        }
        sleeper = { try await Task.sleep(nanoseconds: $0) }
        taskResponseSleeper = { try await Task.sleep(nanoseconds: $0) }
        taskIDProvider = { UUID().uuidString }
        nowNanos = { DispatchTime.now().uptimeNanoseconds }
    }

    init(
        idleTimeoutNanos: UInt64,
        taskResponseTimeoutNanos: UInt64 = 5_000_000_000,
        factory: @escaping TransportFactory,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        taskResponseSleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        taskIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        nowNanos: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.idleTimeoutNanos = idleTimeoutNanos
        self.taskResponseTimeoutNanos = taskResponseTimeoutNanos
        self.factory = factory
        self.sleeper = sleeper
        self.taskResponseSleeper = taskResponseSleeper
        self.taskIDProvider = taskIDProvider
        self.nowNanos = nowNanos
    }

    public func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String] = { _ in [] },
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void = { _ in }
    ) async throws -> String {
        let request = Self.request(for: config)
        let replayableAudio = ReplayableAudio(source: audio)
        defer { replayableAudio.cancel() }
        let callbackState = TaskCallbackState()
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let lease = try await acquire(request: request)
            do {
                let transcript = try await runAttempt(
                    lease: lease,
                    config: config,
                    audio: replayableAudio,
                    callbackState: callbackState,
                    onFinalSentence: onFinalSentence,
                    onTaskStarted: onTaskStarted)
                await release(lease)
                return transcript
            } catch {
                await invalidate(lease)
                if error is CancellationError { throw error }
                attempt += 1
                guard attempt < 2 else { throw error }
            }
        }
    }

    public func shutdown() async {
        idleCloseTask?.cancel()
        idleCloseTask = nil
        idleGeneration = nil
        guard let connection else { return }
        self.connection = nil
        await connection.transport.close()
    }

    private func runAttempt(
        lease: Lease,
        config: QwenRunTaskCaptureConfig,
        audio: ReplayableAudio,
        callbackState: TaskCallbackState,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        let nowNanos = self.nowNanos
        let responseTimeout = taskResponseTimeoutNanos
        let responseSleeper = taskResponseSleeper
        let attemptContext = await callbackState.contextForNextAttempt(
            fallback: config.context)
        let attemptConfig: QwenRunTaskCaptureConfig = {
            var resolved = config
            resolved.context = attemptContext
            return resolved
        }()
        let attempt = Attempt(
            transport: lease.transport,
            taskID: taskIDProvider())
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: AttemptResult.self) { group in
                group.addTask {
                    while true {
                        let event = try await attempt.receive()
                        if case let .sentence(id, text, true) = event,
                           await callbackState.shouldForward(id: id, text: text),
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let updatedContext = await onFinalSentence(text)
                            await callbackState.recordLatestContext(updatedContext)
                            try? await attempt.sendContinueTask(context: updatedContext)
                        }
                        guard let outcome = await attempt.handle(event) else { continue }
                        switch outcome {
                        case let .final(text):
                            return .transcript(text)
                        case let .failed(message):
                            throw QwenRunTaskSessionError.taskFailed(message)
                        }
                    }
                }
                group.addTask {
                    let runTaskSentAt = nowNanos()
                    try await attempt.sendRunTask(.init(config: attemptConfig))
                    guard try await Self.awaitStarted(
                        attempt: attempt,
                        transport: lease.transport,
                        timeoutNanos: responseTimeout,
                        sleeper: responseSleeper) else {
                        throw QwenRunTaskSessionError.taskEndedBeforeStart
                    }
                    let startedAt = nowNanos()
                    await onTaskStarted(.init(
                        reusedConnection: lease.reused,
                        runTaskToStartedNanos: startedAt >= runTaskSentAt
                            ? startedAt - runTaskSentAt
                            : 0))
                    for await pcm in audio.replayingStream() {
                        try Task.checkCancellation()
                        try await attempt.sendAudio(pcm)
                    }
                    try Task.checkCancellation()
                    try await attempt.finish()
                    return .senderFinished
                }

                var finalTimeoutArmed = false
                while let result = try await group.next() {
                    switch result {
                    case .senderFinished where !finalTimeoutArmed:
                        finalTimeoutArmed = true
                        group.addTask {
                            try await responseSleeper(responseTimeout)
                            await lease.transport.close()
                            throw QwenRunTaskSessionError.taskResponseTimedOut
                        }
                    case .senderFinished:
                        continue
                    case let .transcript(text):
                        group.cancelAll()
                        return text
                    }
                }
                throw QwenRunTaskSessionError.taskEndedWithoutFinal
            }
        } onCancel: {
            Task { await lease.transport.close() }
        }
    }

    private func acquire(request: URLRequest) async throws -> Lease {
        idleCloseTask?.cancel()
        idleCloseTask = nil
        idleGeneration = nil
        let key = ConnectionKey(request)
        if var current = connection {
            guard !current.inUse else { throw QwenRunTaskSessionError.connectionBusy }
            if current.key == key, await current.transport.isViable {
                current.inUse = true
                connection = current
                return Lease(id: current.id, transport: current.transport, reused: true)
            }
            connection = nil
            await current.transport.close()
        }
        let transport = try await factory(request)
        let id = UUID()
        connection = Connection(id: id, key: key, transport: transport, inUse: true)
        return Lease(id: id, transport: transport, reused: false)
    }

    private func release(_ lease: Lease) async {
        guard var current = connection, current.id == lease.id else { return }
        current.inUse = false
        connection = current
        let id = current.id
        let generation = UUID()
        idleGeneration = generation
        idleCloseTask = Task { [weak self, sleeper, idleTimeoutNanos] in
            do {
                try await sleeper(idleTimeoutNanos)
            } catch {
                return
            }
            await self?.expireIdleConnection(id: id, generation: generation)
        }
    }

    private func invalidate(_ lease: Lease) async {
        guard let current = connection, current.id == lease.id else { return }
        connection = nil
        idleCloseTask?.cancel()
        idleCloseTask = nil
        idleGeneration = nil
        await current.transport.close()
    }

    private func expireIdleConnection(id: UUID, generation: UUID) async {
        guard idleGeneration == generation,
              let current = connection, current.id == id, !current.inUse else { return }
        connection = nil
        idleCloseTask = nil
        idleGeneration = nil
        await current.transport.close()
    }

    private static func request(for config: QwenRunTaskCaptureConfig) -> URLRequest {
        var request = URLRequest(url: config.endpoint.url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        if !config.endpoint.usesDedicatedHost,
           let workspaceID = QwenRunTaskEndpoint.normalizedWorkspaceID(config.endpoint.workspaceID) {
            request.setValue(workspaceID, forHTTPHeaderField: "X-DashScope-WorkSpace")
        }
        return request
    }

    private static func awaitStarted(
        attempt: Attempt,
        transport: any QwenRunTaskTransport,
        timeoutNanos: UInt64,
        sleeper: @escaping Sleeper
    ) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { await attempt.awaitStarted() }
            group.addTask {
                try await sleeper(timeoutNanos)
                await transport.close()
                throw QwenRunTaskSessionError.taskResponseTimedOut
            }
            defer { group.cancelAll() }
            return try await group.next() ?? false
        }
    }
}
