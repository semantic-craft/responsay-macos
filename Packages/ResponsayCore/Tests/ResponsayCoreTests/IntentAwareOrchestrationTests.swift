import Foundation
import Testing
@testable import ResponsayCore

@Test @MainActor func intentAwareFinal_runsVerifiedTracerThroughSingleInsertChain() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "周三开会，不对，周四开会"
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let compiler = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        let plan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(
                    winner: .init(sources[2]),
                    loser: .init(sources[0]),
                    cue: .init(sources[1]))
            ])
        return try JSONEncoder().encode(plan)
    }
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        intentCompiler: compiler,
        intentRoutePolicyProvider: { .injectedCompiler })

    vm.push(outputMode: .intentAwareDictation)
    await vm.release()

    #expect(vm.phase == .idle)
    #expect(inserter.inserted == ["周四开会"])
    // #565: the approved final persists (route + coarse outcome) with the raw utterance NOT retained,
    // and the session's raw-bearing state is cleared once the terminal insert completes.
    let saved = try #require(try store.recent(10).first)
    #expect(saved.sourceText == nil)                  // 原口述未保存
    #expect(saved.idiomatic == "周四开会")             // superseded 周三 gone — the verified final only
    #expect(saved.intentRoute == .intentPlan)
    #expect(saved.intentOutcome == .inserted)
    #expect(try store.recent(10).count == 1)
    #expect(vm.captureResult == nil)                  // raw sourceTranscript no longer lingers
    #expect(vm.transcript.isEmpty)
    #expect(vm.revertableInsertion == nil)
    #expect(vm.correctionOffer == nil)
}

@Test @MainActor func noIntentControlRoute_survivesRealOrchestrationBoundary() async throws {
    let response = Data(#"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#.utf8)
    let fixture = makeIntentVM(response: response)

    fixture.vm.push(outputMode: .intentAwareDictation)
    await fixture.vm.release()

    #expect(fixture.vm.phase == .idle)
    #expect(fixture.inserter.inserted == ["A"])
    // #565: the 普通整理 route (valid plan, noIntentControl) still persists its approved final.
    let saved = try #require(try fixture.store.recent(10).first)
    #expect(saved.sourceText == nil)
    #expect(saved.idiomatic == "A")
    #expect(saved.intentRoute == .ordinaryPolished)
    #expect(saved.intentOutcome == .inserted)
    #expect(fixture.vm.captureResult == nil)
}

@Test @MainActor func intentAwareNonInsertOutcomes_remainDistinctAndHaveZeroSideEffects() async throws {
    let needsReviewJSON = #"{"version":1,"decision":"needsReview","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#
    let needsReview = makeIntentVM(response: Data(needsReviewJSON.utf8))

    needsReview.vm.push(outputMode: .intentAwareDictation)
    await needsReview.vm.release()

    #expect(needsReview.vm.phase == .review)
    #expect(needsReview.vm.intentCaptureState == .needsReview(.compilerRequested))
    #expect(needsReview.vm.reviewState.kind == .intentNeedsReview)
    #expect(needsReview.inserter.inserted.isEmpty)
    #expect(needsReview.vm.captureResult == nil)
    #expect(needsReview.vm.copiedText.isEmpty)
    #expect(try needsReview.store.recent(10).isEmpty)

    let safeUnavailable = makeIntentVM(response: Data(#"{"finalText":"unchecked"}"#.utf8))

    safeUnavailable.vm.push(outputMode: .intentAwareDictation)
    await safeUnavailable.vm.release()

    #expect(safeUnavailable.vm.phase == .review)
    #expect(safeUnavailable.vm.intentCaptureState == .safeUnavailable(.invalidPlan))
    #expect(safeUnavailable.vm.reviewState.kind == .intentSafeUnavailable)
    #expect(safeUnavailable.inserter.inserted.isEmpty)
    #expect(safeUnavailable.vm.captureResult == nil)
    #expect(safeUnavailable.vm.copiedText.isEmpty)
    #expect(try safeUnavailable.store.recent(10).isEmpty)
}

@Test @MainActor func cancelledIntentCompilation_ignoresLateInsertableCompletion() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "A"
    let compiler = SuspendedIntentCompiler()
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        intentCompiler: compiler,
        intentRoutePolicyProvider: { .injectedCompiler })

    vm.push(outputMode: .intentAwareDictation)
    let release = Task { @MainActor in await vm.release() }
    for _ in 0..<500 {
        if await compiler.isAwaitingCompletion() { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await compiler.isAwaitingCompletion())
    #expect(vm.phase == .thinking)

    await vm.cancelCapture()
    await compiler.complete(with: Data(#"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#.utf8))
    await release.value

    #expect(vm.phase == .idle)
    #expect(vm.transcript.isEmpty)
    #expect(vm.captureResult == nil)
    #expect(vm.intentCaptureState == nil)
    #expect(vm.copiedText.isEmpty)
    #expect(vm.revertableInsertion == nil)
    #expect(vm.correctionOffer == nil)
    #expect(inserter.inserted.isEmpty)
    #expect(try store.recent(10).isEmpty)
}

@Test @MainActor func cancelledIntentFinalization_ignoresLateFailure() async throws {
    let speech = SuspendedFailingSpeechService()
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        intentCompiler: RecordingIntentCompiler(),
        intentRoutePolicyProvider: { .injectedCompiler })

    vm.push(outputMode: .intentAwareDictation)
    let release = Task { @MainActor in await vm.release() }
    for _ in 0..<500 {
        if speech.isAwaitingCompletion { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(speech.isAwaitingCompletion)

    await vm.cancelCapture()
    speech.fail()
    await release.value

    #expect(vm.phase == .idle)
    #expect(vm.errorMessage == nil)
    #expect(vm.transcript.isEmpty)
    #expect(vm.captureResult == nil)
    #expect(vm.intentCaptureState == nil)
    #expect(vm.copiedText.isEmpty)
    #expect(inserter.inserted.isEmpty)
    #expect(try store.recent(10).isEmpty)
}

@Test @MainActor func intentAwarePartialsOnlyPreviewAndCompilerReceivesFinalSnapshot() async throws {
    let speech = IntentPartialSpeechService(finalTranscript: "最终文本")
    let compiler = RecordingIntentCompiler()
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let context = ExpressionContext(appName: "Notes", textBeforeCursor: "before")
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        contextProvider: { context },
        intentCompiler: compiler,
        intentRoutePolicyProvider: { .injectedCompiler })
    vm.locale = .chinese

    vm.push(outputMode: .intentAwareDictation)
    speech.emitPartial("尚未完成")
    try await waitUntil("intent partial 仅进入预览") { vm.transcript == "尚未完成" }

    #expect(await compiler.inputs().isEmpty)
    #expect(inserter.inserted.isEmpty)
    #expect(vm.copiedText.isEmpty)
    #expect(try store.recent(10).isEmpty)

    await vm.release()

    let inputs = await compiler.inputs()
    #expect(inputs.count == 1)
    #expect(inputs.first?.finalTranscript == "最终文本")
    #expect(inputs.first?.locale.rawValue == CaptureLocale.chinese.rawValue)
    #expect(inputs.first?.allowedContext == context)
    #expect(inputs.first?.routePolicy == .injectedCompiler)
    #expect(inserter.inserted == ["最终文本"])
    // #565: after the insert completes the approved final is persisted (raw not retained).
    let saved = try #require(try store.recent(10).first)
    #expect(saved.sourceText == nil)
    #expect(saved.idiomatic == "最终文本")
    #expect(saved.intentOutcome == .inserted)
}

@Test @MainActor func nonIntentModesAndPreformedText_neverInvokeIntentCompiler() async {
    let compiler = RecordingIntentCompiler()
    let modes: [QuickCaptureViewModel.OutputMode] = [
        .rawTranscript,
        .polishedTranscript,
        .rewriteSameLanguage,
        .idiomaticPreview,
        .coachRewrite,
        .translateSpoken,
        .translateWritten,
        .translatePreview,
        .teachingFeedback,
        .askSelection
    ]

    for mode in modes {
        let vm = QuickCaptureViewModel(
            speech: MockSpeechCaptureService(),
            coach: MockCoachAPI(),
            store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")),
            inserter: MockTextInserter(),
            intentCompiler: compiler,
            intentRoutePolicyProvider: { .injectedCompiler })
        await vm.processText("A", outputMode: mode)
    }

    #expect(await compiler.inputs().isEmpty)

    let preformed = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")),
        inserter: MockTextInserter(),
        intentCompiler: compiler,
        intentRoutePolicyProvider: { .injectedCompiler })
    await preformed.processText("A", outputMode: .intentAwareDictation)

    #expect(await compiler.inputs().isEmpty)
    #expect(preformed.intentCaptureState == .safeUnavailable(.invalidSource))
}

@MainActor
private func makeIntentVM(response: Data) -> (
    vm: QuickCaptureViewModel,
    inserter: MockTextInserter,
    store: FileCaptureStore
) {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "A"
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        intentCompiler: FixtureIntentCompiler { _ in response },
        intentRoutePolicyProvider: { .injectedCompiler })
    return (vm, inserter, store)
}

private actor SuspendedIntentCompiler: IntentPlanCompiler {
    private var continuation: CheckedContinuation<Data, Error>?

    func compile(_ input: IntentCompilerInput) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func isAwaitingCompletion() -> Bool {
        continuation != nil
    }

    func complete(with data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

private actor RecordingIntentCompiler: IntentPlanCompiler {
    private var recordedInputs = [IntentCompilerInput]()

    func compile(_ input: IntentCompilerInput) async throws -> Data {
        recordedInputs.append(input)
        let plan = IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: [])
        return try JSONEncoder().encode(plan)
    }

    func inputs() -> [IntentCompilerInput] {
        recordedInputs
    }
}

@MainActor
private final class SuspendedFailingSpeechService: SpeechCaptureService {
    let levels: AsyncStream<Float>
    private var continuation: CheckedContinuation<String, Error>?

    var isAwaitingCompletion: Bool { continuation != nil }

    init() {
        (levels, _) = AsyncStream.makeStream(of: Float.self)
    }

    func start(locale: CaptureLocale) throws {}

    func stop() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func fail() {
        continuation?.resume(throwing: URLError(.timedOut))
        continuation = nil
    }
}

@MainActor
private final class IntentPartialSpeechService: SpeechCaptureService, SpeechPartialTranscriptProviding {
    let levels: AsyncStream<Float>
    let partialTranscripts: AsyncStream<String>
    private let partialContinuation: AsyncStream<String>.Continuation
    private let finalTranscript: String

    init(finalTranscript: String) {
        self.finalTranscript = finalTranscript
        (levels, _) = AsyncStream.makeStream(of: Float.self)
        (partialTranscripts, partialContinuation) = AsyncStream.makeStream(of: String.self)
    }

    func start(locale: CaptureLocale) throws {}
    func stop() async throws -> String { finalTranscript }
    func emitPartial(_ text: String) { partialContinuation.yield(text) }
}
