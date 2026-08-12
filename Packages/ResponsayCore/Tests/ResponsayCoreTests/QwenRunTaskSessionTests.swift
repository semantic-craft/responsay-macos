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
            Issue.record("Expected the third rejected task to surface its session error.")
        } catch QwenRunTaskSessionError.taskFailed(let message) {
            #expect(message == "TEST_ERROR: rejected")
        } catch {
            Issue.record("Unexpected bounded-retry error: \(error)")
        }
        let next = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x02])]))

        #expect(next == "next task")
        #expect(await factory.makeCount == 4)
        await session.shutdown()
    }

    /// If the server ever reuses a `sentence_id` with *different* text (numbering reset after a
    /// long pause), both sentences must survive — keying finals by id alone silently replaced
    /// everything said before the pause.
    @Test func reusedSentenceIDWithDifferentTextAppendsInsteadOfReplacing() async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(
                transcripts: [],
                finishFrames: [
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "停顿前的内容。", isFinal: true)),
                    .text(sentenceEventMessage(
                        taskID: "task-1", id: 1, text: "停顿后的内容。", isFinal: true)),
                    .text(serverEventMessage(taskID: "task-1", event: "task-finished")),
                ]),
        ])
        let ids = LockedTaskIDs(["task-1"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })

        let transcript = try await session.transcribe(
            config: config(),
            audio: completedAudio([Data([0x01])]))

        #expect(transcript == "停顿前的内容。停顿后的内容。")
        await session.shutdown()
    }

    /// The post-`finish-task` wait must grow with the recording so a reconnect replay of a long
    /// capture is not cut off at the flat handshake timeout, and must stay capped.
    @Test func finalWaitScalesWithRecordedAudioAndIsCapped() {
        let base: UInt64 = 5_000_000_000
        #expect(QwenRunTaskSession.finalWaitNanos(base: base, audioBytes: 0) == base)
        // 60 s of 16 kHz mono Int16 audio = 1,920,000 bytes → +30 s of grace.
        #expect(QwenRunTaskSession.finalWaitNanos(base: base, audioBytes: 1_920_000)
                == 35_000_000_000)
        // 15 min of audio would scale past the cap; the wait clamps at 90 s.
        #expect(QwenRunTaskSession.finalWaitNanos(base: base, audioBytes: 28_800_000)
                == 90_000_000_000)
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

    @Test(
        "Retry restores the callback Context, including an empty fail-closed result",
        arguments: [["updated context"], []] as [[String]]
    )
    func retryRestoresTheContextReturnedByTheFinalSentenceCallback(
        updatedContext: [String]
    ) async throws {
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: ["replayed sentence"], failingAfterFinalRunOrdinals: [1]),
            .init(transcripts: ["replayed sentence"]),
        ])
        let ids = LockedTaskIDs(["task-1", "task-2"])
        let session = QwenRunTaskSession(
            idleTimeoutNanos: .max,
            factory: { request in try await factory.make(request) },
            taskIDProvider: { ids.next() })
        let callbacks = SentenceSink()

        let transcript = try await session.transcribe(
            config: config(context: ["original context"]),
            audio: completedAudio([Data([0x01])]),
            onFinalSentence: {
                await callbacks.append($0)
                return updatedContext
            })

        #expect(transcript == "replayed sentence")
        #expect(await callbacks.values == ["replayed sentence"])
        let failed = try #require(await factory.transport(at: 0))
        let recovered = try #require(await factory.transport(at: 1))
        #expect(await failed.runTasks.map(\.context) == [["original context"]])
        #expect(await recovered.runTasks.map(\.context) == [updatedContext])
        #expect(await recovered.continueContexts.isEmpty)
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

    @Test func repeatedFinalResponseTimeoutIsTerminalAfterBoundedRetries() async throws {
        let timeoutSleeper = TimeoutOnCallsSleeper(timeoutCalls: [2, 4, 6])
        let factory = ScriptedQwenTransportFactory([
            .init(transcripts: [], hangsAfterStart: true),
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

        #expect(await factory.makeCount == 3)
        #expect(await factory.transport(at: 0)?.isClosed == true)
        #expect(await factory.transport(at: 1)?.isClosed == true)
        #expect(await factory.transport(at: 2)?.isClosed == true)
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
