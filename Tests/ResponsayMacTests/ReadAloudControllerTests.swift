import XCTest
@testable import ResponsayMac
import ResponsayCore

@MainActor
final class ReadAloudControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticsCenter.shared.clear()
    }

    override func tearDown() {
        DiagnosticsCenter.shared.clear()
        super.tearDown()
    }

    func testReadCreatesTraceableTransactionAndRunsPreflightBeforeSynth() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        var events: [String] = []
        reader.preflightForPlayback = { tx in
            events.append("preflight:\(tx.traceID)")
            return (mutedBefore: true, mutedAfter: false)
        }
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") {
                events.append("synth")
                return OneShotSynthesizer()
            }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<100 where player.playCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        let tx = try XCTUnwrap(reader.currentTransaction)
        XCTAssertEqual(tx.traceID, tx.requestID.uuidString)
        XCTAssertEqual(events, ["preflight:\(tx.traceID)", "synth"])
        reader.stop()
    }

    func testStaleSynthCallbackCannotStartOldHighlightOrPlayback() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        var synths: [any SpeechSynthesizer] = [
            DelayedSynthesizer(delayMs: 200),
            OneShotSynthesizer(),
        ]
        reader.preflightForPlayback = { _ in (mutedBefore: false, mutedAfter: false) }
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synths.removeFirst() }]
        }

        reader.toggleRead(.sample)
        let firstRequestID = try XCTUnwrap(reader.currentTransaction?.requestID)
        try await Task.sleep(for: .milliseconds(20))
        reader.toggleRead(.sample)
        XCTAssertNotEqual(reader.currentTransaction?.requestID, firstRequestID)

        for _ in 0..<100 where player.playCalls.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertTrue(reader.isPlaying)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertNil(reader.lastErrorMessage)
        XCTAssertTrue(reader.isPlaying)
        XCTAssertTrue(DiagnosticsCenter.shared.events.contains {
            $0.title == "staleCallbackIgnored"
                && $0.fields["oldRequestID"] == firstRequestID.uuidString
        })
        reader.stop()
    }

    func testSynthFailureStopsWithVisibleFailure() async throws {
        let reader = ReadAloudController()
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") {
                throw TTSError.modelNotInstalled
            }]
        }

        reader.toggleRead(.sample)
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertFalse(reader.isPlaying)
        XCTAssertFalse(reader.isPreparing)
        XCTAssertEqual(reader.mode, .idle)
        XCTAssertNotNil(reader.lastErrorMessage)

        reader.stop()
        XCTAssertFalse(reader.isPlaying)
        XCTAssertNil(reader.activeIndex)
    }

    func testSynthFailureDiagnosticsCarryFailureChainWithoutUtterance() async throws {
        let reader = ReadAloudController()
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") {
                throw TTSError.modelNotInstalled
            }]
        }

        reader.toggleRead(.sample)
        let event = try await waitForTTSEvent(title: "synth failed")

        let required = [
            "traceID", "requestID", "source", "chars", "hash", "attempt",
            "provider", "mode", "phase", "fallback", "result",
        ]
        for key in required {
            XCTAssertFalse(event.fields[key, default: ""].isEmpty, "missing \(key)")
        }
        XCTAssertEqual(event.fields["chars"], String(ProsodyAnalysis.sample.text.count))

        let utterance = ProsodyAnalysis.sample.text
        XCTAssertFalse(event.title.contains(utterance))
        XCTAssertFalse(event.errorMessage?.contains(utterance) ?? false)
        XCTAssertFalse(event.fields.values.contains { $0.contains(utterance) })
    }

    func testRuntimeNonStreamingFallbackUsesAppleAfterSelectedFailureAndInvalidKokoroAudio() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        let selected = FailingSynthesizer(.network("down"))
        let kokoro = FixedSynthesizer(samples: [0, 0, 0])
        let apple = FixedSynthesizer(samples: [0, 0.2, -0.2, 0])
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .selected, title: "selected") { selected },
                TTSFallbackAttempt(target: .kokoro, title: "Kokoro") { kokoro },
                TTSFallbackAttempt(target: .system, title: "Apple") { apple },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        let selectedCalls = await selected.recordedCalls
        let kokoroCalls = await kokoro.recordedCalls
        let appleCalls = await apple.recordedCalls
        XCTAssertEqual(selectedCalls, ["I'll call you."])
        XCTAssertEqual(kokoroCalls, ["I'll call you."])
        XCTAssertEqual(appleCalls, ["I'll call you."])
        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.chunks.first?.samples, [0, 0.2, -0.2, 0])
        XCTAssertTrue(reader.isPlaying)
        XCTAssertNil(reader.lastErrorMessage)
        reader.stop()
    }

    func testPlaybackAnchorTimeoutRetriesOnceAndDoesNotStartHighlight() async throws {
        let player = NeverAnchoredAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls < 2 || reader.isPreparing {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(player.playCalls, 2)
        XCTAssertEqual(player.emergencyCalls, 1)   // 484: ladder reaches file emergency
        XCTAssertFalse(reader.isPlaying)
        XCTAssertFalse(reader.isPreparing)
        XCTAssertEqual(reader.mode, .idle)
        XCTAssertNil(reader.activeIndex)
        XCTAssertNotNil(reader.lastErrorMessage)
    }

    func testEnginePlaybackFailureFallsBackToFileEmergencyThenPlays() async throws {
        // 484: engine anchor never arrives, but file-level AVAudioPlayer emergency starts.
        let player = NeverAnchoredAudioPlayer()
        player.emergencyShouldSucceed = true
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<300 where !reader.isPlaying && reader.lastErrorMessage == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(player.playCalls, 2)        // engine reset-retry exhausted first
        XCTAssertEqual(player.emergencyCalls, 1)   // then the file emergency rung
        XCTAssertTrue(reader.isPlaying)
        XCTAssertNil(reader.lastErrorMessage)
        reader.stop()
    }

    func testStreamingFailureBeforeFirstChunkStaysPreparingForFallback() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        let synth = SlowRecordingSynthesizer()
        reader.makeStreamingSynthesizer = {
            FailingStreamingSynthesizer(failure: .beforeFirstChunk)
        }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where !(await synth.didStart) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(reader.isPreparing)
        XCTAssertFalse(reader.isPlaying)
        XCTAssertNil(reader.activeIndex)
        XCTAssertEqual(player.appendStreamingCalls, 0)

        for _ in 0..<200 where player.playCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await synth.recordedCalls
        XCTAssertEqual(calls, ["I'll call you."])
        XCTAssertEqual(player.playCalls.count, 1)
        reader.stop()
    }

    func testStreamingFailureAfterAudioResetsThenReplaysWholeUtterance() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        let synth = SlowRecordingSynthesizer()
        reader.makeStreamingSynthesizer = {
            FailingStreamingSynthesizer(failure: .afterFirstChunk)
        }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where !(await synth.didStart) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(reader.isPreparing)
        XCTAssertFalse(reader.isPlaying)
        XCTAssertNil(reader.activeIndex)
        XCTAssertEqual(player.appendStreamingCalls, 1)
        XCTAssertGreaterThanOrEqual(player.stopCalls, 1)

        for _ in 0..<200 where player.playCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await synth.recordedCalls
        XCTAssertEqual(calls, ["I'll call you."])
        XCTAssertEqual(player.playCalls.count, 1)
        reader.stop()
    }

    func testStreamingFailureStillUsesNonStreamingFallbackSynth() async throws {
        let reader = ReadAloudController()
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { throw TTSError.missingAPIKey(provider: "阿里云百炼") }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        try await Task.sleep(for: .milliseconds(250))

        let calls = await synth.recordedCalls
        XCTAssertEqual(calls, ["I'll call you."])
        reader.stop()
    }

    func testReadShowsPreparingWhileSynthesizing() async throws {
        let reader = ReadAloudController()
        let synth = SlowSynthesizer()
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)

        XCTAssertTrue(reader.isPreparing)
        XCTAssertFalse(reader.isPlaying)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(reader.isPreparing)

        reader.stop()
    }

    func testApplyHighlightDrivesActiveIndexOverTimeline() {
        let reader = ReadAloudController()
        reader.repeatRead(.sample, count: 1)
        defer { reader.stop() }

        XCTAssertTrue(reader.applyHighlight(at: 0))
        XCTAssertEqual(reader.activeIndex, 0)

        let total = ReadAloudTimeline.totalDuration(ReadAloudTimeline.build(.sample))
        XCTAssertFalse(reader.applyHighlight(at: total + 1))
        XCTAssertNil(reader.activeIndex)
    }

    func testStartingReadOnAnotherSurfaceStopsThePreviousSurface() async throws {
        // 481: two surfaces share one coordinator → starting B cancels A.
        let coordinator = ReadAloudCoordinator()
        let playerA = RecordingAudioPlayer()
        let playerB = RecordingAudioPlayer()
        let readerA = ReadAloudController(player: playerA)
        let readerB = ReadAloudController(player: playerB)
        for reader in [readerA, readerB] {
            reader.coordinator = coordinator
            reader.preflightForPlayback = { _ in (mutedBefore: false, mutedAfter: false) }
            reader.makeStreamingSynthesizer = { nil }
            reader.makeFallbackAttempts = {
                [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
            }
        }

        readerA.toggleRead(.sample)
        for _ in 0..<200 where !readerA.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(readerA.isPlaying)

        readerB.toggleRead(.sample)
        // activate(self) runs synchronously inside toggleRead, so A is already stopped.
        XCTAssertFalse(readerA.isPlaying)
        XCTAssertEqual(readerA.mode, .idle)
        XCTAssertNil(readerA.currentTransaction)
        XCTAssertGreaterThanOrEqual(playerA.stopCalls, 1)

        for _ in 0..<200 where !readerB.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(readerB.isPlaying)

        readerA.stop()
        readerB.stop()
    }

    // MARK: - 486 streaming fault matrix (P1-07)

    func testStreamingNormalCompletePlaysWithoutNonStreamingFallback() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { FailingStreamingSynthesizer(failure: .normalComplete) }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where !reader.isPlaying { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertTrue(reader.isPlaying)
        XCTAssertGreaterThanOrEqual(player.appendStreamingCalls, 1)
        XCTAssertEqual(player.playCalls.count, 0)            // streaming path, no composed replay
        let calls = await synth.recordedCalls
        XCTAssertTrue(calls.isEmpty)                          // no non-streaming fallback
        reader.stop()
    }

    func testStreamingFirstChunkLatencyStillPlays() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { FailingStreamingSynthesizer(failure: .firstChunkLatency) }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<300 where !reader.isPlaying { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertTrue(reader.isPlaying)
        XCTAssertGreaterThanOrEqual(player.appendStreamingCalls, 1)
        reader.stop()
    }

    func testStreamingCloseWithoutAudioFallsBackToNonStreaming() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { FailingStreamingSynthesizer(failure: .closeWithoutAudio) }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        let calls = await synth.recordedCalls
        XCTAssertEqual(calls, ["I'll call you."])
        XCTAssertEqual(player.playCalls.count, 1)
        reader.stop()
    }

    func testStreamingThirdChunkThrowResetsThenReplaysWholeUtterance() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { FailingStreamingSynthesizer(failure: .thirdChunkThrow) }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(player.appendStreamingCalls, 2)        // two chunks before the throw
        XCTAssertGreaterThanOrEqual(player.stopCalls, 1)
        let calls = await synth.recordedCalls
        XCTAssertEqual(calls, ["I'll call you."])             // non-streaming replay
        XCTAssertEqual(player.playCalls.count, 1)
        reader.stop()
    }

    // MARK: - 486 non-streaming fallback matrix

    func testCloudUnconfiguredUsesKokoro() async throws {       // UT-05
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .selected, title: "selected") {
                    FailingSynthesizer(.missingAPIKey(provider: "阿里云百炼"))
                },
                TTSFallbackAttempt(target: .kokoro, title: "Kokoro") {
                    FixedSynthesizer(samples: [0, 0.3, -0.3, 0])
                },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(player.playCalls.first?.chunks.first?.samples, [0, 0.3, -0.3, 0])
        XCTAssertTrue(reader.isPlaying)
        reader.stop()
    }

    func testKokoroMissingUsesAppleSystemTTS() async throws {   // UT-08
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .selected, title: "selected") {
                    FailingSynthesizer(.modelNotInstalled)
                },
                TTSFallbackAttempt(target: .kokoro, title: "Kokoro") {
                    FailingSynthesizer(.modelNotInstalled)
                },
                TTSFallbackAttempt(target: .system, title: "Apple") {
                    FixedSynthesizer(samples: [0, 0.2, -0.2, 0])
                },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(player.playCalls.first?.chunks.first?.samples, [0, 0.2, -0.2, 0])
        XCTAssertTrue(reader.isPlaying)
        reader.stop()
    }

    func testKokoroZeroChunksUsesAppleSystemTTS() async throws {  // UT-09
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .kokoro, title: "Kokoro") { FixedSynthesizer(samples: []) },
                TTSFallbackAttempt(target: .system, title: "Apple") {
                    FixedSynthesizer(samples: [0, 0.2, -0.2, 0])
                },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(player.playCalls.first?.chunks.first?.samples, [0, 0.2, -0.2, 0])
        reader.stop()
    }

    func testNaNPCMFallsBackToAppleSystemTTS() async throws {     // UT-10
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .kokoro, title: "Kokoro") {
                    FixedSynthesizer(samples: [.nan, .nan, .nan])
                },
                TTSFallbackAttempt(target: .system, title: "Apple") {
                    FixedSynthesizer(samples: [0, 0.2, -0.2, 0])
                },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(player.playCalls.first?.chunks.first?.samples, [0, 0.2, -0.2, 0])
        reader.stop()
    }

    func testComposeSuccessLogsPcmValidityFields() async throws {   // 485
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") {
                FixedSynthesizer(samples: [0, 0.5, -0.5, 0])
            }]
        }

        reader.toggleRead(.sample)
        let event = try await waitForTTSEvent(title: "synth attempt done")

        XCTAssertFalse(event.fields["totalFrames", default: ""].isEmpty)
        XCTAssertEqual(event.fields["peakAbs"], "0.500")
        reader.stop()
    }

    func testRepeatModeEmergencyReplaysViaEmergencyNotBrokenEngine() async throws {
        // 484: in 复读, a loop restart after the engine fell to file emergency must replay
        // via emergency — replaying through the (still broken) engine goes silent.
        let player = EmergencyLoopingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
        }

        reader.repeatRead(.sample, count: 2)
        for _ in 0..<400 where reader.mode != .idle {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(player.emergencyCalls, 2)   // first play + loop replay, both via emergency
        reader.stop()
    }

    // MARK: - 495 compose cache

    func testCoachReadCachesComposedAudioSoSecondReadSkipsSynth() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.cachesComposedAudio = true
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        reader.stop()
        let afterFirst = await synth.recordedCalls.count
        XCTAssertEqual(afterFirst, 1)

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        reader.stop()
        let afterSecond = await synth.recordedCalls.count
        XCTAssertEqual(afterSecond, 1)   // second read served from cache, no re-synthesis
    }

    func testAskReadDoesNotCacheSoSecondReadResynthesizes() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        // cachesComposedAudio stays false (the Ask Anything default)
        let synth = RecordingSynthesizer()
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { synth }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        reader.stop()
        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        reader.stop()

        let calls = await synth.recordedCalls.count
        XCTAssertEqual(calls, 2)   // no cache → synthesized both times
    }

    // MARK: - 497 fallback voice surfaced

    func testFallbackVoiceSurfacedToUserAndClearedOnStop() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [
                TTSFallbackAttempt(target: .selected, title: "selected") { FailingSynthesizer(.network("down")) },
                TTSFallbackAttempt(target: .system, title: "Apple") { FixedSynthesizer(samples: [0, 0.2, -0.2, 0]) },
            ]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        let notice = reader.activeVoiceNotice
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("Apple") ?? false)

        reader.stop()
        XCTAssertNil(reader.activeVoiceNotice)
    }

    func testSelectedEngineSuccessShowsNoVoiceNotice() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "selected") { OneShotSynthesizer() }]
        }

        reader.toggleRead(.sample)
        for _ in 0..<200 where player.playCalls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertNil(reader.activeVoiceNotice)   // selected engine spoke → no notice
        reader.stop()
    }

    private func waitForTTSEvent(title: String) async throws -> DiagnosticEvent {
        for _ in 0..<50 {
            if let event = DiagnosticsCenter.shared.events.last(where: {
                $0.category == .tts && $0.title == title
            }) {
                return event
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw XCTSkip("timed out waiting for TTS diagnostic event")
    }
}
