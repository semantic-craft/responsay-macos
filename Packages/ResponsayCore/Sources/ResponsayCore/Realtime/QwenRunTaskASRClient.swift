import Foundation

public enum QwenRunTaskTransportMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
}

/// Narrow WebSocket surface used by the run-task client. Keeping the task codec independent from
/// `URLSessionWebSocketTask` lets the connection lifecycle and reconnect path run deterministically
/// in tests without a live DashScope socket.
public protocol QwenRunTaskTransport: Sendable {
    var isViable: Bool { get async }
    func send(_ message: QwenRunTaskTransportMessage) async throws
    func receive() async throws -> QwenRunTaskTransportMessage
    func close() async
}

public final class QwenURLSessionWebSocketTransport: QwenRunTaskTransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    public init(task: URLSessionWebSocketTask, resume: Bool = false) {
        self.task = task
        if resume { task.resume() }
    }

    public var isViable: Bool {
        get async { task.state == .running }
    }

    public func send(_ message: QwenRunTaskTransportMessage) async throws {
        switch message {
        case let .text(text):
            try await task.send(.string(text))
        case let .data(data):
            try await task.send(.data(data))
        }
    }

    public func receive() async throws -> QwenRunTaskTransportMessage {
        switch try await task.receive() {
        case let .string(text): return .text(text)
        case let .data(data): return .data(data)
        @unknown default: throw RealtimeTransportError.unsupportedFrame
        }
    }

    public func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Drives 百炼 实时语音识别 over the run-task WebSocket protocol in push-to-talk shape:
/// `run-task` → wait for `task-started` → binary PCM frames while the hotkey is held →
/// `finish-task` on release → `task-finished` carries the joined 整段 transcript.
///
/// Two things this protocol forces that the retired OmniRealtime client did not:
/// - **Audio may not be sent before `task-started`.** `awaitStarted()` is the gate; it is
///   released by any terminal event too, so a `task-failed` during handshake can never wedge
///   the sender task (and therefore never wedge `stop()`).
/// - **Results arrive per sentence**, not as one cumulative hypothesis. Finals are collected
///   per `sentence_id` (so a duplicate/replayed event cannot double-append) and merged with
///   `TranscriptJoiner.mergeSegments`, which already exists for exactly this wire shape.
///
/// `send*`/`receive` touch the live socket (mic + network) — the HITL boundary; the fold and
/// the wire codec are unit-tested offline.
public actor QwenRunTaskASRClient {
    private let transport: any QwenRunTaskTransport
    private let taskID: String

    private var finalsByID: [Int: String] = [:]
    private var finalOrder: [Int] = []
    private var pendingPartial = ""
    private var finishSent = false

    private var startState: StartState = .waiting
    private var startWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private enum StartState: Equatable {
        case waiting
        case started
        case terminated
    }

    public init(transport: any QwenRunTaskTransport, taskID: String = UUID().uuidString) {
        self.transport = transport
        self.taskID = taskID
    }

    public init(transport: URLSessionWebSocketTask, taskID: String = UUID().uuidString) {
        self.transport = QwenURLSessionWebSocketTransport(task: transport)
        self.taskID = taskID
    }

    // MARK: - Client → server

    public func sendRunTask(
        model: String,
        sampleRate: Int = 16_000,
        hotwords: [String] = [],
        precompiledVocabularyID: String? = nil,
        languageHints: [String] = [],
        context: [String] = [],
        heartbeat: Bool = false
    ) async throws {
        try await sendText(QwenRunTaskASRProtocol.runTask(
            taskID: taskID, model: model, sampleRate: sampleRate,
            hotwords: hotwords, precompiledVocabularyID: precompiledVocabularyID,
            languageHints: languageHints, context: context,
            heartbeat: heartbeat))
    }

    /// Updates context while the task is active. A trailing final can arrive after `finish-task`;
    /// in that case the text is still recorded locally by the caller, but no invalid wire event is
    /// sent after finishing has begun.
    public func sendContinueTask(context: [String]) async throws {
        guard !finishSent, !context.isEmpty else { return }
        try await sendText(QwenRunTaskASRProtocol.continueTask(taskID: taskID, context: context))
    }

    /// Suspends until `task-started` arrives (returns true) or the task ends first (false).
    public func awaitStarted() async -> Bool {
        switch startState {
        case .started: return true
        case .terminated: return false
        case .waiting:
            let waiterID = UUID()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: false)
                    } else {
                        startWaiters[waiterID] = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancelStartWaiter(waiterID) }
            }
        }
    }

    /// Mono PCM goes on the wire as a **binary** frame — this protocol does not base64 audio
    /// into JSON the way the OmniRealtime one did.
    public func sendAudio(_ pcm: Data) async throws {
        try await transport.send(.data(pcm))
    }

    /// All audio sent (hotkey released) → the server flushes the trailing sentence and ends.
    public func finish() async throws {
        finishSent = true
        try await sendText(QwenRunTaskASRProtocol.finishTask(taskID: taskID))
    }

    private func sendText(_ data: Data) async throws {
        try await transport.send(.text(String(data: data, encoding: .utf8) ?? ""))
    }

    // MARK: - Server → client

    public func receive() async throws -> QwenRunTaskASRProtocol.ServerEvent {
        switch try await transport.receive() {
        case let .text(text):
            return QwenRunTaskASRProtocol.decode(Data(text.utf8))
        case let .data(data):
            return QwenRunTaskASRProtocol.decode(data)
        }
    }

    public func handleEvent(_ event: QwenRunTaskASRProtocol.ServerEvent) -> TranscriptUpdate? {
        switch event {
        case .started:
            resolveStart(.started)
            return nil

        case let .sentence(id, text, isFinal):
            if isFinal {
                if finalsByID.updateValue(text, forKey: id) == nil { finalOrder.append(id) }
                pendingPartial = ""
            } else {
                pendingPartial = text
            }
            return .partial(preview: transcript)

        case .finished:
            resolveStart(.terminated)
            return .final(transcript: transcript)

        case let .failure(message):
            resolveStart(.terminated)
            return .failed(message: message.isEmpty ? nil : message)

        case .ignored:
            return nil
        }
    }

    /// Finals in `sentence_id` arrival order, plus any sentence still open. `mergeSegments`
    /// collapses an exact boundary overlap, so a trailing partial that the final then repeats
    /// cannot duplicate text.
    public var transcript: String {
        var segments = finalOrder.compactMap { finalsByID[$0] }
        if !pendingPartial.isEmpty { segments.append(pendingPartial) }
        return TranscriptJoiner.mergeSegments(segments)
    }

    private func resolveStart(_ state: StartState) {
        guard startState == .waiting else { return }
        startState = state
        let waiters = Array(startWaiters.values)
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: state == .started) }
    }

    private func cancelStartWaiter(_ id: UUID) {
        startWaiters.removeValue(forKey: id)?.resume(returning: false)
    }
}
