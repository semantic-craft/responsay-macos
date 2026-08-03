import Foundation
import Testing
@testable import ResponsayCore

@Suite("QwenRunTaskSession reuse")
struct QwenRunTaskSessionTests {
    @Test func sequentialTasksReuseOneSocketWithFreshTaskState() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["first transcript", "second transcript"],
                  duplicateFinalSentence: true),
        ])
        let ids = LockedTaskIDs(["task-1", "task-2"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })
        let sentences = SentenceSink()

        let first = try await session.transcribe(
            config: config(locale: .chinese),
            audio: completedAudio([Data([0x01])]),
            onFinalSentence: { await sentences.append($0); return [] })
        let second = try await session.transcribe(
            config: config(locale: .english),
            audio: completedAudio([Data([0x02])]),
            onFinalSentence: { await sentences.append($0); return [] })

        #expect(first == "first transcript")
        #expect(second == "second transcript")
        #expect(await factory.makeCount == 1)
        let transport = try #require(await factory.transport(at: 0))
        #expect(await transport.taskIDs == ["task-1", "task-2"])
        #expect(await transport.audioByTask == [
            "task-1": [Data([0x01])],
            "task-2": [Data([0x02])],
        ])
        #expect(await sentences.values == ["first transcript", "second transcript"])
        await session.shutdown()
    }

    @Test func failedReusedTaskReconnectsAndReplaysTheWholeRecording() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["warmup"], failingRunOrdinals: [2]),
            .init(transcripts: ["recovered"]),
        ])
        let ids = LockedTaskIDs(["task-1", "task-2", "task-3"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })

        _ = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]))
        let liveAudio = QwenReplayableAudioBuffer()
        liveAudio.append(Data([0x0A]))
        let recovery = Task {
            try await session.transcribe(config: config(), audio: liveAudio)
        }
        let fresh = try await waitForTransport(factory, index: 1)
        try await waitUntilAsync("replacement Qwen task starts") { await fresh.runCount == 1 }
        liveAudio.append(Data([0x0B]))
        liveAudio.finish()
        let recovered = try await recovery.value

        #expect(recovered == "recovered")
        #expect(await factory.makeCount == 2)
        let stale = try #require(await factory.transport(at: 0))
        #expect(await stale.taskIDs == ["task-1", "task-2"])
        #expect(await stale.isClosed)
        #expect(await fresh.taskIDs == ["task-3"])
        #expect(await fresh.audioByTask["task-3"] == [Data([0x0A]), Data([0x0B])])
        await session.shutdown()
    }

    @Test func serverClosedIdleSocketFallsBackToFreshConnection() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["warmup"]),
            .init(transcripts: ["after server close"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })

        _ = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]))
        let stale = try #require(await factory.transport(at: 0))
        await stale.simulateServerClose()

        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]))

        #expect(transcript == "after server close")
        #expect(await factory.makeCount == 2)
        await session.shutdown()
    }

    @Test func repeatedTaskFailureIsBoundedAndNextTaskUsesFreshConnection() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: [], failingRunOrdinals: [1]),
            .init(transcripts: [], failingRunOrdinals: [1]),
            .init(transcripts: ["next task"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })

        await #expect(throws: QwenRunTaskSessionError.self) {
            _ = try await session.transcribe(
                config: config(),
                audio: completedAudio([Data([0x01])]))
        }
        let next = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]))

        #expect(next == "next task")
        #expect(await factory.makeCount == 3)
        await session.shutdown()
    }

    @Test func cancellationInvalidatesTheSocketAndDoesNotLeakTaskState() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: [], hangsAfterStart: true),
            .init(transcripts: ["after cancellation"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })
        let liveAudio = QwenReplayableAudioBuffer()
        liveAudio.append(Data([0x01]))
        let cancelled = Task {
            try await session.transcribe(config: config(), audio: liveAudio)
        }
        let first = try await waitForTransport(factory, index: 0)
        try await waitUntilAsync("first Qwen task starts") {
            await first.runCount == 1
        }

        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        try await waitUntilAsync("cancelled transport closes") { await first.isClosed }

        let next = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]))
        #expect(next == "after cancellation")
        #expect(await factory.makeCount == 2)
        await session.shutdown()
    }

    @Test func finalResponseTimeoutReconnectsAndReplaysWithoutDroppingAudio() async throws {
        let timeoutSleeper = TimeoutOnCallSleeper(timeoutCall: 2)
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: [], hangsAfterStart: true),
            .init(transcripts: ["recovered after timeout"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            taskResponseTimeoutNanos: 123,
            factory: { request in try await factory.make(request) },
            taskResponseSleeper: { _ in try await timeoutSleeper.sleep() })
        let frames = [Data([0x01]), Data([0x02]), Data([0x03])]

        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio(frames))

        #expect(transcript == "recovered after timeout")
        #expect(await factory.makeCount == 2)
        let timedOut = try #require(await factory.transport(at: 0))
        let recovered = try #require(await factory.transport(at: 1))
        #expect(await timedOut.isClosed)
        let recoveredTaskID = try #require(await recovered.taskIDs.first)
        #expect(await recovered.audioByTask[recoveredTaskID] == frames)
        await session.shutdown()
    }

    @Test func idleExpiryClosesTheRetainedSocket() async throws {
        let sleeper = ManualSleeper()
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["first"]),
            .init(transcripts: ["second"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: 45_000_000_000,
            factory: { request in try await factory.make(request) },
            sleeper: { _ in try await sleeper.wait() })

        _ = try await session.transcribe(config: config(), audio: completedAudio([Data([0x01])]))
        let first = try #require(await factory.transport(at: 0))
        try await waitUntilAsync("idle timer arms") { await sleeper.isWaiting }
        await sleeper.fire()
        try await waitUntilAsync("idle transport closes") { await first.isClosed }

        _ = try await session.transcribe(config: config(), audio: completedAudio([Data([0x02])]))
        #expect(await factory.makeCount == 2)
        await session.shutdown()
    }

    /// Deterministic latency comparison: a new scripted transport advances the virtual clock by
    /// 120 ms for its handshake; a task on the retained transport advances only 5 ms for run-task.
    /// This pins the exact latency component the live opt-in test measures against DashScope.
    @Test func reuseAvoidsTheSecondHandshakeLatency() async throws {
        let clock = VirtualNanosecondClock()
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["first", "second"], firstStartNanos: 120_000_000,
                  reusedStartNanos: 5_000_000, clock: clock),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            nowNanos: { clock.now })
        let metrics = MetricSink()

        _ = try await session.transcribe(
            config: config(), audio: completedAudio([Data([0x01])]),
            onTaskStarted: { await metrics.append($0) })
        _ = try await session.transcribe(
            config: config(), audio: completedAudio([Data([0x02])]),
            onTaskStarted: { await metrics.append($0) })

        #expect(await metrics.values == [
            .init(reusedConnection: false, runTaskToStartedNanos: 120_000_000),
            .init(reusedConnection: true, runTaskToStartedNanos: 5_000_000),
        ])
        print("QWEN_REUSE_LATENCY_DETERMINISTIC fresh_ms=120.0 reused_ms=5.0 saved_ms=115.0")
        await session.shutdown()
    }

    private func config(locale: CaptureLocale = .chinese) -> QwenRunTaskCaptureConfig {
        QwenRunTaskCaptureConfig(
            endpoint: .init(region: .china),
            apiKey: "synthetic-test-key",
            captureLocale: locale)
    }

    private func completedAudio(_ frames: [Data]) -> QwenReplayableAudioBuffer {
        let audio = QwenReplayableAudioBuffer()
        for frame in frames { audio.append(frame) }
        audio.finish()
        return audio
    }

    private func waitForTransport(
        _ factory: ScriptedQwenTransportFactory,
        index: Int
    ) async throws -> ScriptedQwenTransport {
        try await waitUntilAsync("Qwen transport \(index) exists") {
            await factory.transport(at: index) != nil
        }
        return try #require(await factory.transport(at: index))
    }
}

private struct ScriptedTransportPlan: Sendable {
    var transcripts: [String]
    var failingRunOrdinals: Set<Int> = []
    var hangsAfterStart = false
    var duplicateFinalSentence = false
    var firstStartNanos: UInt64 = 0
    var reusedStartNanos: UInt64 = 0
    var clock: VirtualNanosecondClock?
}

private actor ScriptedQwenTransportFactory {
    private let plans: [ScriptedTransportPlan]
    private(set) var transports: [ScriptedQwenTransport] = []

    init(_ plans: [ScriptedTransportPlan]) { self.plans = plans }

    var makeCount: Int { transports.count }

    func make(_ request: URLRequest) throws -> any QwenRunTaskTransport {
        _ = request
        guard transports.count < plans.count else { throw ScriptedTransportError.noPlan }
        let transport = ScriptedQwenTransport(plan: plans[transports.count])
        transports.append(transport)
        return transport
    }

    func transport(at index: Int) -> ScriptedQwenTransport? {
        transports.indices.contains(index) ? transports[index] : nil
    }
}

private actor ScriptedQwenTransport: QwenRunTaskTransport {
    private let plan: ScriptedTransportPlan
    private let continuation: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.Continuation
    private let receiver: ScriptedStreamReceiver
    private var currentTaskID: String?
    private(set) var taskIDs: [String] = []
    private(set) var audioByTask: [String: [Data]] = [:]
    private(set) var isClosed = false

    init(plan: ScriptedTransportPlan) {
        self.plan = plan
        let pair = AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.makeStream()
        continuation = pair.continuation
        receiver = ScriptedStreamReceiver(pair.stream)
    }

    var runCount: Int { taskIDs.count }
    var isViable: Bool { !isClosed }

    func send(_ message: QwenRunTaskTransportMessage) async throws {
        guard !isClosed else { throw ScriptedTransportError.closed }
        switch message {
        case let .data(data):
            guard let currentTaskID else { throw ScriptedTransportError.audioBeforeTask }
            audioByTask[currentTaskID, default: []].append(data)
        case let .text(text):
            let root = try json(text)
            let header = root["header"] as? [String: Any]
            let action = header?["action"] as? String
            let taskID = header?["task_id"] as? String ?? ""
            switch action {
            case "run-task":
                currentTaskID = taskID
                taskIDs.append(taskID)
                let ordinal = taskIDs.count
                if plan.failingRunOrdinals.contains(ordinal) {
                    continuation.yield(.text(serverEvent(
                        taskID: taskID,
                        event: "task-failed",
                        errorMessage: "rejected")))
                    return
                }
                if let clock = plan.clock {
                    clock.advance(by: ordinal == 1 ? plan.firstStartNanos : plan.reusedStartNanos)
                }
                continuation.yield(.text(serverEvent(taskID: taskID, event: "task-started")))
            case "finish-task":
                if plan.hangsAfterStart { return }
                let ordinal = taskIDs.count
                guard plan.transcripts.indices.contains(ordinal - 1) else {
                    throw ScriptedTransportError.noTranscript
                }
                let transcript = plan.transcripts[ordinal - 1]
                continuation.yield(.text(sentenceEvent(taskID: taskID, text: transcript)))
                if plan.duplicateFinalSentence {
                    continuation.yield(.text(sentenceEvent(taskID: taskID, text: transcript)))
                }
                continuation.yield(.text(serverEvent(taskID: taskID, event: "task-finished")))
                currentTaskID = nil
            default:
                break
            }
        }
    }

    func receive() async throws -> QwenRunTaskTransportMessage {
        guard let message = try await receiver.next() else { throw ScriptedTransportError.closed }
        return message
    }

    func close() async {
        isClosed = true
        continuation.finish()
    }

    func simulateServerClose() {
        isClosed = true
        continuation.finish()
    }

    private func json(_ text: String) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ScriptedTransportError.malformedJSON
        }
        return root
    }

    private func serverEvent(
        taskID: String,
        event: String,
        errorMessage: String? = nil
    ) -> String {
        var header = ["task_id": taskID, "event": event]
        if let errorMessage {
            header["error_code"] = "TEST_ERROR"
            header["error_message"] = errorMessage
        }
        let root: [String: Any] = ["header": header, "payload": [:] as [String: Any]]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return String(decoding: data, as: UTF8.self)
    }

    private func sentenceEvent(taskID: String, text: String) -> String {
        let root: [String: Any] = [
            "header": ["task_id": taskID, "event": "result-generated"],
            "payload": ["output": ["sentence": [
                "sentence_id": 1, "text": text, "sentence_end": true,
            ]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return String(decoding: data, as: UTF8.self)
    }
}

private final class ScriptedStreamReceiver: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.Iterator

    init(_ stream: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> QwenRunTaskTransportMessage? {
        try await iterator.next()
    }
}

private enum ScriptedTransportError: Error {
    case noPlan
    case closed
    case audioBeforeTask
    case noTranscript
    case malformedJSON
}

private final class LockedTaskIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? UUID().uuidString : values.removeFirst()
    }
}

private final class VirtualNanosecondClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var now: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by nanos: UInt64) {
        lock.lock()
        value += nanos
        lock.unlock()
    }
}

private actor SentenceSink {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor MetricSink {
    private(set) var values: [QwenRunTaskStartMetric] = []
    func append(_ value: QwenRunTaskStartMetric) { values.append(value) }
}

private actor ManualSleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fire() {
        continuation?.resume()
        continuation = nil
    }
}

private actor TimeoutOnCallSleeper {
    private let timeoutCall: Int
    private var callCount = 0

    init(timeoutCall: Int) {
        self.timeoutCall = timeoutCall
    }

    func sleep() async throws {
        callCount += 1
        if callCount == timeoutCall { return }
        try await Task.sleep(nanoseconds: .max)
    }
}

private func waitUntilAsync(
    _ what: String,
    timeout: Duration = .seconds(5),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw WaitUntilTimeout(what: what) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
