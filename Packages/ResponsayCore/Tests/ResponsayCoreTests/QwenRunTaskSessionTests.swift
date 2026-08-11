import Foundation
import Testing
@testable import ResponsayCore

@Suite("QwenRunTaskSession")
struct QwenRunTaskSessionTests {
    @Test func streamsAudioThroughTheSessionInterface() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["streamed transcript"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        continuation.yield(Data([0x01]))
        continuation.finish()

        let transcript = try await session.transcribe(config: config(), audio: audio)

        #expect(transcript == "streamed transcript")
        let transport = try #require(await factory.transport(at: 0))
        let taskID = try #require(await transport.taskIDs.first)
        #expect(await transport.audioByTask[taskID] == [Data([0x01])])
        await session.shutdown()
    }

    @Test func waitsForTaskStartedBeforeSendingBufferedAudio() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["gated transcript"], automaticStart: false),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })
        let transcription = Task {
            try await session.transcribe(
                config: config(),
                audio: completedAudio([Data([0x01])]))
        }
        let transport = try await waitForTransport(factory, index: 0)
        try await waitUntilAsync("run-task is sent") { await transport.runCount == 1 }

        #expect(await transport.audioByTask.isEmpty)
        await transport.emitStarted()

        #expect(try await transcription.value == "gated transcript")
        let taskID = try #require(await transport.taskIDs.first)
        #expect(await transport.audioByTask[taskID] == [Data([0x01])])
        await session.shutdown()
    }

    @Test func decodesAndFoldsTransportFramesInsideTheSession() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(
                transcripts: [],
                finishFrames: [
                    .text("not json"),
                    .text(sentenceEventMessage(
                        taskID: "ignored", id: 0, text: "", isFinal: false, heartbeat: true)),
                    .data(Data(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "你好世", isFinal: false).utf8)),
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "你好世界。", isFinal: true)),
                    .data(Data(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "你好世界。", isFinal: true).utf8)),
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 2, text: "这是法言。", isFinal: true)),
                    .text(serverEventMessage(taskID: "task-1", event: "task-finished")),
                ]),
        ])
        let ids = LockedTaskIDs(["task-1"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })
        let callbacks = SentenceSink()

        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]),
            onFinalSentence: { await callbacks.append($0); return [] })

        #expect(transcript == "你好世界。这是法言。")
        #expect(await callbacks.values == ["你好世界。", "这是法言。"])
        await session.shutdown()
    }

    @Test func sendsConfiguredRunTaskAndFinishThroughTheTransportSeam() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["configured transcript"]),
        ])
        let ids = LockedTaskIDs(["task-wire"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })

        _ = try await session.transcribe(
            config: config(
                locale: .mixed,
                hotwords: ["Westlaw", "法研 Metis", "Westlaw"],
                precompiledVocabularyID: "vocab-curated-a1b2c3",
                context: ["drop me", "one", "two", "three", "four", "five"],
                heartbeat: true),
            audio: completedAudio([Data([0x01])]))

        let transport = try #require(await factory.transport(at: 0))
        #expect(await transport.runTasks == [
            .init(
                taskID: "task-wire",
                streaming: "duplex",
                taskGroup: "audio",
                task: "asr",
                function: "recognition",
                model: QwenRunTaskEndpoint.defaultModel,
                parameterKeys: ["format", "sample_rate", "language_hints", "vocabulary", "heartbeat"],
                format: "pcm",
                sampleRate: 16_000,
                languageHints: ["zh", "en"],
                vocabulary: ["Westlaw": 4, "法研 Metis": 4],
                vocabularyID: nil,
                heartbeat: true,
                context: ["one", "two", "three", "four", "five"]),
        ])
        #expect(await transport.finishTasks == [
            .init(taskID: "task-wire", streaming: "duplex", hasEmptyInput: true),
        ])
        await session.shutdown()
    }

    @Test func finalSentenceCallbackRefreshesContextWhileAudioIsOpen() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(
                transcripts: [],
                framesAfterStart: [
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "first sentence。", isFinal: true)),
                ],
                finishFrames: [
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 2, text: "second sentence。", isFinal: true)),
                    .text(serverEventMessage(taskID: "task-1", event: "task-finished")),
                ]),
        ])
        let ids = LockedTaskIDs(["task-1"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        let transcription = Task {
            try await session.transcribe(
                config: config(),
                audio: audio,
                onFinalSentence: { _ in ["updated context"] })
        }
        let transport = try await waitForTransport(factory, index: 0)
        try await waitUntilAsync("continue-task carries refreshed context") {
            await transport.continueContexts == [["updated context"]]
        }

        continuation.finish()

        #expect(try await transcription.value == "first sentence。second sentence。")
        #expect(await transport.continueContexts == [["updated context"]])
        await session.shutdown()
    }

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

    @Test func reusedSocketKeepsVocabularySelectionTaskScoped() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["compiled vocabulary", "instant vocabulary"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })

        _ = try await session.transcribe(
            config: config(precompiledVocabularyID: "vocab-curated-a1b2c3"),
            audio: completedAudio([Data([0x01])]))
        _ = try await session.transcribe(
            config: config(locale: .mixed, hotwords: ["法研 Metis"]),
            audio: completedAudio([Data([0x02])]))

        let transport = try #require(await factory.transport(at: 0))
        #expect(await transport.vocabularyIDs == ["vocab-curated-a1b2c3", nil])
        #expect(await transport.vocabularies == [nil, ["法研 Metis": 4]])
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
        let (liveAudio, audioContinuation) = AsyncStream.makeStream(of: Data.self)
        audioContinuation.yield(Data([0x0A]))
        let recovery = Task {
            try await session.transcribe(config: config(), audio: liveAudio)
        }
        let fresh = try await waitForTransport(factory, index: 1)
        try await waitUntilAsync("replacement Qwen task starts") { await fresh.runCount == 1 }
        audioContinuation.yield(Data([0x0B]))
        audioContinuation.finish()
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

        do {
            _ = try await session.transcribe(
                config: config(),
                audio: completedAudio([Data([0x01])]))
            Issue.record("Expected the second rejected task to surface its session error.")
        } catch QwenRunTaskSessionError.taskFailed(let message) {
            #expect(message == "TEST_ERROR: rejected")
        } catch {
            Issue.record("Unexpected bounded-retry error: \(error)")
        }
        let next = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]))

        #expect(next == "next task")
        #expect(await factory.makeCount == 3)
        await session.shutdown()
    }

    @Test func finalSentenceCallbackRunsOnceAcrossRetryReplay() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["warmup", "replayed sentence"],
                  failingAfterFinalRunOrdinals: [2]),
            .init(transcripts: ["replayed sentence"]),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })

        _ = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]))
        let callbacks = SentenceSink()
        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]),
            onFinalSentence: { await callbacks.append($0); return [] })

        #expect(transcript == "replayed sentence")
        #expect(await callbacks.values == ["replayed sentence"])
        #expect(await factory.makeCount == 2)
        await session.shutdown()
    }

    @Test func contextRecorderReceivesOnlyTheRawFinalSentenceNotPartialHypotheses() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["raw server final"], emitsPartialBeforeFinal: true),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) })
        let callbacks = SentenceSink()

        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]),
            onFinalSentence: { await callbacks.append($0); return [] })

        #expect(transcript == "raw server final")
        #expect(await callbacks.values == ["raw server final"])
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
        let (liveAudio, audioContinuation) = AsyncStream.makeStream(of: Data.self)
        audioContinuation.yield(Data([0x01]))
        let cancelled = Task {
            try await session.transcribe(config: config(), audio: liveAudio)
        }
        let first = try await waitForTransport(factory, index: 0)
        try await waitUntilAsync("first Qwen task starts") {
            await first.runCount == 1
        }

        cancelled.cancel()
        audioContinuation.finish()
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
        let timeoutSleeper = TimeoutOnCallsSleeper(timeoutCalls: [2])
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

    @Test func repeatedFinalResponseTimeoutIsTerminalAfterOneRetry() async throws {
        let timeoutSleeper = TimeoutOnCallsSleeper(timeoutCalls: [2, 4])
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: [], hangsAfterStart: true),
            .init(transcripts: [], hangsAfterStart: true),
        ])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            taskResponseTimeoutNanos: 123,
            factory: { request in try await factory.make(request) },
            taskResponseSleeper: { _ in try await timeoutSleeper.sleep() })

        do {
            _ = try await session.transcribe(
                config: config(),
                audio: completedAudio([Data([0x01])]))
            Issue.record("Expected the bounded retry to end in a terminal timeout.")
        } catch QwenRunTaskSessionError.taskResponseTimedOut {
            // Expected: the timeout remains observable through the session interface.
        } catch {
            Issue.record("Unexpected terminal timeout error: \(error)")
        }

        #expect(await factory.makeCount == 2)
        #expect(await factory.transport(at: 0)?.isClosed == true)
        #expect(await factory.transport(at: 1)?.isClosed == true)
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

    private func config(
        locale: CaptureLocale = .chinese,
        hotwords: [String] = [],
        precompiledVocabularyID: String? = nil,
        context: [String] = [],
        heartbeat: Bool = false
    ) -> QwenRunTaskCaptureConfig {
        QwenRunTaskCaptureConfig(
            endpoint: .init(region: .china),
            apiKey: "synthetic-test-key",
            hotwords: hotwords,
            precompiledVocabularyID: precompiledVocabularyID,
            context: context,
            captureLocale: locale,
            heartbeat: heartbeat)
    }

    private func completedAudio(_ frames: [Data]) -> AsyncStream<Data> {
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        for frame in frames { continuation.yield(frame) }
        continuation.finish()
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
    var failingAfterFinalRunOrdinals: Set<Int> = []
    var hangsAfterStart = false
    var duplicateFinalSentence = false
    var emitsPartialBeforeFinal = false
    var automaticStart = true
    var framesAfterStart: [QwenRunTaskTransportMessage] = []
    var finishFrames: [QwenRunTaskTransportMessage]?
    var firstStartNanos: UInt64 = 0
    var reusedStartNanos: UInt64 = 0
    var clock: VirtualNanosecondClock?
}

private struct RunTaskObservation: Sendable, Equatable {
    var taskID: String
    var streaming: String?
    var taskGroup: String?
    var task: String?
    var function: String?
    var model: String?
    var parameterKeys: Set<String>
    var format: String?
    var sampleRate: Int?
    var languageHints: [String]?
    var vocabulary: [String: Int]?
    var vocabularyID: String?
    var heartbeat: Bool?
    var context: [String]
}

private struct FinishTaskObservation: Sendable, Equatable {
    var taskID: String
    var streaming: String?
    var hasEmptyInput: Bool
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
    private var startedTaskIDs = Set<String>()
    private(set) var taskIDs: [String] = []
    private(set) var audioByTask: [String: [Data]] = [:]
    private(set) var vocabularyIDs: [String?] = []
    private(set) var vocabularies: [[String: Int]?] = []
    private(set) var runTasks: [RunTaskObservation] = []
    private(set) var finishTasks: [FinishTaskObservation] = []
    private(set) var continueContexts: [[String]] = []
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
            guard let currentTaskID,
                  startedTaskIDs.contains(currentTaskID) else {
                throw ScriptedTransportError.audioBeforeStart
            }
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
                let payload = root["payload"] as? [String: Any]
                let parameters = payload?["parameters"] as? [String: Any]
                vocabularyIDs.append(parameters?["vocabulary_id"] as? String)
                vocabularies.append(parameters?["vocabulary"] as? [String: Int])
                runTasks.append(.init(
                    taskID: taskID,
                    streaming: header?["streaming"] as? String,
                    taskGroup: payload?["task_group"] as? String,
                    task: payload?["task"] as? String,
                    function: payload?["function"] as? String,
                    model: payload?["model"] as? String,
                    parameterKeys: Set(parameters?.keys.map { $0 } ?? []),
                    format: parameters?["format"] as? String,
                    sampleRate: parameters?["sample_rate"] as? Int,
                    languageHints: parameters?["language_hints"] as? [String],
                    vocabulary: parameters?["vocabulary"] as? [String: Int],
                    vocabularyID: parameters?["vocabulary_id"] as? String,
                    heartbeat: parameters?["heartbeat"] as? Bool,
                    context: context(from: (payload?["input"] as? [String: Any])?["context"])))
                let ordinal = taskIDs.count
                if plan.failingRunOrdinals.contains(ordinal) {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID,
                        event: "task-failed",
                        errorMessage: "rejected")))
                    return
                }
                if plan.automaticStart {
                    emitStart(taskID: taskID, ordinal: ordinal)
                }
            case "finish-task":
                let payload = root["payload"] as? [String: Any]
                let input = payload?["input"] as? [String: Any]
                finishTasks.append(.init(
                    taskID: taskID,
                    streaming: header?["streaming"] as? String,
                    hasEmptyInput: input?.isEmpty == true))
                if plan.hangsAfterStart { return }
                if let finishFrames = plan.finishFrames {
                    for frame in finishFrames { continuation.yield(frame) }
                    currentTaskID = nil
                    startedTaskIDs.remove(taskID)
                    return
                }
                let ordinal = taskIDs.count
                guard plan.transcripts.indices.contains(ordinal - 1) else {
                    throw ScriptedTransportError.noTranscript
                }
                let transcript = plan.transcripts[ordinal - 1]
                if plan.emitsPartialBeforeFinal {
                    continuation.yield(.text(sentenceEventMessage(
                        taskID: taskID, id: 1, text: "partial hypothesis", isFinal: false)))
                }
                continuation.yield(.text(sentenceEventMessage(
                    taskID: taskID, id: 1, text: transcript, isFinal: true)))
                if plan.duplicateFinalSentence {
                    continuation.yield(.text(sentenceEventMessage(
                        taskID: taskID, id: 1, text: transcript, isFinal: true)))
                }
                if plan.failingAfterFinalRunOrdinals.contains(ordinal) {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID,
                        event: "task-failed",
                        errorMessage: "connection lost after final")))
                } else {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID, event: "task-finished")))
                }
                currentTaskID = nil
                startedTaskIDs.remove(taskID)
            case "continue-task":
                let payload = root["payload"] as? [String: Any]
                let input = payload?["input"] as? [String: Any]
                continueContexts.append(context(from: input?["context"]))
            default:
                break
            }
        }
    }

    func emitStarted() {
        guard let taskID = currentTaskID else { return }
        emitStart(taskID: taskID, ordinal: taskIDs.count)
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

    private func emitStart(taskID: String, ordinal: Int) {
        guard startedTaskIDs.insert(taskID).inserted else { return }
        if let clock = plan.clock {
            clock.advance(by: ordinal == 1 ? plan.firstStartNanos : plan.reusedStartNanos)
        }
        continuation.yield(.text(serverEventMessage(taskID: taskID, event: "task-started")))
        for frame in plan.framesAfterStart { continuation.yield(frame) }
    }

    private func context(from value: Any?) -> [String] {
        guard let messages = value as? [[String: Any]] else { return [] }
        return messages.compactMap { message in
            let content = message["content"] as? [[String: Any]]
            return content?.first?["text"] as? String
        }
    }
}

private func serverEventMessage(
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

private func sentenceEventMessage(
    taskID: String,
    id: Int,
    text: String,
    isFinal: Bool,
    heartbeat: Bool = false
) -> String {
    let root: [String: Any] = [
        "header": ["task_id": taskID, "event": "result-generated"],
        "payload": ["output": ["sentence": [
            "sentence_id": id,
            "text": text,
            "sentence_end": isFinal,
            "heartbeat": heartbeat,
        ]]],
    ]
    let data = try! JSONSerialization.data(withJSONObject: root)
    return String(decoding: data, as: UTF8.self)
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
    case audioBeforeStart
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

private actor TimeoutOnCallsSleeper {
    private let timeoutCalls: Set<Int>
    private var callCount = 0

    init(timeoutCalls: Set<Int>) {
        self.timeoutCalls = timeoutCalls
    }

    func sleep() async throws {
        callCount += 1
        if timeoutCalls.contains(callCount) { return }
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
