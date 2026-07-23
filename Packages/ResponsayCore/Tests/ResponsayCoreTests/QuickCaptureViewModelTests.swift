import Testing
import Foundation
@testable import ResponsayCore

// Hold-mode(按住说)路径:push() 开始,release() 停并处理,落到 .review。
@MainActor
private func makeHoldVM(transcript: String, result: ExpressionResult? = nil, expressError: CoachAPIError? = nil)
    -> (QuickCaptureViewModel, FileCaptureStore) {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = transcript
    let coach = MockCoachAPI(result: result, error: expressError)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = FileCaptureStore(fileURL: url)
    return (QuickCaptureViewModel(speech: speech, coach: coach, store: store, inserter: MockTextInserter()), store)
}

@Test @MainActor func hold_happyPath_landsInReview_andSaves() async throws {
    let (vm, store) = makeHoldVM(
        transcript: "i want fix bug",
        result: ExpressionResult(idiomatic: "I want to fix the bug.", original: "i want fix bug", reasons: ["缺 to"]))
    vm.push()
    #expect(vm.phase == .listening)
    await vm.release()
    #expect(vm.phase == .review)
    #expect(vm.result?.idiomatic == "I want to fix the bug.")
    #expect(try store.recent(10).first?.idiomatic == "I want to fix the bug.")
}

@Test @MainActor func hold_emptyTranscript_returnsToIdle_savesNothing() async throws {
    let (vm, store) = makeHoldVM(transcript: "   ")
    vm.push(); await vm.release()
    #expect(vm.phase == .idle)
    #expect(vm.result == nil)
    #expect(try store.recent(10).isEmpty)
}

@Test @MainActor func hold_expressFails_setsError_butPreservesRecognizedTranscript() async throws {
    // Failed LLM transform keeps the recognized transcript in history (never lost), still errors.
    let (vm, store) = makeHoldVM(transcript: "hello", expressError: .message("backend down"))
    vm.push(); await vm.release()
    #expect(vm.phase == .error)
    #expect(vm.errorMessage?.isEmpty == false)
    let saved = try store.recent(10)
    #expect(saved.count == 1)
    #expect(saved.first?.sourceText == "hello")
}

// 187 — teaching mode (express + analyze) degrades gracefully when prosody (/analyze, cloud)
// fails: the local English coach result still shows; prosody is skipped with a needs-network note.
@MainActor
private func makeTeachingVM(transcript: String, coach: MockCoachAPI)
    -> (QuickCaptureViewModel, FileCaptureStore) {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = transcript
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = FileCaptureStore(fileURL: url)
    return (QuickCaptureViewModel(speech: speech, coach: coach, store: store, inserter: MockTextInserter()), store)
}

@Test @MainActor func teaching_expresses_autoInsertsAndReviews() async throws {
    let (vm, store) = makeTeachingVM(
        transcript: "我看看",
        coach: MockCoachAPI(
            result: ExpressionResult(idiomatic: "Let me check.", original: "我看看", reasons: ["更口语"])))

    vm.push(outputMode: .teachingFeedback)
    await vm.release()

    #expect(vm.phase == .review)
    #expect(vm.result?.idiomatic == "Let me check.")
    #expect(vm.result?.reasons == ["更口语"])
    // The coaching was saved.
    #expect(try store.recent(10).first?.idiomatic == "Let me check.")
}

@Test @MainActor func teaching_expressFails_stillErrors() async throws {
    let (vm, store) = makeTeachingVM(transcript: "我看看", coach: MockCoachAPI(error: .message("backend down")))

    vm.push(outputMode: .teachingFeedback)
    await vm.release()

    #expect(vm.phase == .error)
    #expect(try store.recent(10).isEmpty)
}

@Test @MainActor func coachCapture_usesFaithfulSpeechProfile() async throws {
    let speech = MockSpeechCaptureService()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter())

    await vm.toggle(outputMode: .coachRewrite)

    #expect(speech.captureProfiles == [.faithful])
}

@Test @MainActor func polishedDictation_usesDictationSpeechProfile() async throws {
    let speech = MockSpeechCaptureService()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter(),
        polisher: MockTextPolishAPI())

    await vm.toggle(outputMode: .polishedTranscript)

    #expect(speech.captureProfiles == [.dictation])
}

// 标点默认开(openless 式自动整理 → 加标点)要对离线无模型用户安全:当 polish(LLM)
// 不可用/抛错时,听写绝不能进 .error,必须退回逐字上屏。
@MainActor private final class ThrowingPolishAPI: TextPolishAPI {
    func polish(_ text: String) async throws -> PolishResult {
        throw CoachAPIError.message("no LLM configured")
    }
}

@Test @MainActor func polishedDictation_degradesToVerbatim_whenPolishUnavailable() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天测试没有模型"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(),
        store: rewriteTmpStore(), inserter: inserter,
        polisher: ThrowingPolishAPI())

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.phase == .idle)                          // not .error
    #expect(vm.errorMessage == nil)
    #expect(inserter.inserted == ["今天测试没有模型"])   // verbatim still landed
}

@Test @MainActor func listeningConsumesPartialTranscriptPreview() async throws {
    let speech = PartialMockSpeechCaptureService()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter())

    await vm.toggle(outputMode: .rawTranscript)
    speech.emitPartial("今天先 smoke")
    try await waitUntil("partialTask 消费到分段预览") { vm.transcript == "今天先 smoke" }

    #expect(vm.transcript == "今天先 smoke")
}

@Test @MainActor func releaseShowsFinalizingUntilSpeechStopReturns() async throws {
    let speech = DelayedStopSpeechCaptureService()
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter)

    vm.push(outputMode: .rawTranscript)
    let releaseTask = Task { @MainActor in await vm.release() }
    // stop continuation 挂上 ⇒ phase/isFinalizing 必已设置,且下面的 finish() 必不落空。
    try await waitUntil("release 跑到 speech.stop() 挂起点") { speech.isStopAwaiting }

    #expect(vm.phase == .thinking)
    #expect(vm.isFinalizingTranscript)

    speech.finish("final text")
    await releaseTask.value

    #expect(vm.phase == .idle)
    #expect(!vm.isFinalizingTranscript)
    #expect(inserter.inserted == ["final text"])
}

@Test @MainActor func finalizingConsumesPostUploadPartialTranscriptPreview() async throws {
    let speech = PartialMockSpeechCaptureService()
    speech.partialsToEmitOnStop = ["Good", "Good morning"]
    speech.stopDelayNanos = 200_000_000
    speech.transcriptToReturn = "Good morning."
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter)

    vm.push(outputMode: .rawTranscript)
    let releaseTask = Task { @MainActor in await vm.release() }

    try await waitUntil("post-upload chunk 更新 finalizing 预览") {
        vm.isFinalizingTranscript && vm.transcript == "Good morning"
    }
    await releaseTask.value

    #expect(vm.phase == .idle)
    #expect(inserter.inserted == ["Good morning."])
}

// 325 slice 3 (TDD): 重改写 applies the SELECTED RewriteStyle. A StylePack
// reaches the rewriter (and must bypass streaming, which can't carry its prompt);
// with no pack selected it falls back to the tone provider.
@MainActor
private final class RecordingRewriteAPI: TextRewriteAPI {
    var lastStyle: RewriteStyle?
    func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        lastStyle = style
        return PolishResult(text: text, original: text, changes: [])
    }
}

@MainActor private func rewriteTmpStore() -> FileCaptureStore {
    FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
}

@Test @MainActor func rewriteAndInsert_appliesSelectedPackStyle() async throws {
    let rewriter = RecordingRewriteAPI()
    let pack = StylePack(id: "p", name: "公文", systemPrompt: "公文风格。", origin: .localImport)
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(), coach: MockCoachAPI(),
        store: rewriteTmpStore(), inserter: MockTextInserter(),
        rewriter: rewriter, rewriteStyleProvider: { .pack(pack) })

    await vm.processText("他不还钱", outputMode: .rewriteSameLanguage)

    #expect(rewriter.lastStyle == .pack(pack))
}

@Test @MainActor func rewriteAndInsert_defaultsToToneWhenNoPackSelected() async throws {
    let rewriter = RecordingRewriteAPI()
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(), coach: MockCoachAPI(),
        store: rewriteTmpStore(), inserter: MockTextInserter(),
        rewriter: rewriter, rewriteToneProvider: { .formal })

    await vm.processText("他不还钱", outputMode: .rewriteSameLanguage)

    #expect(rewriter.lastStyle == .tone(.formal))
}

// 猎虫⑥ F1 — snapOCR 的翻译结果只出卡，绝不触碰宿主（070 验收原文 = capsule
// result card）。旧 .translate 路由带 .replaceSelection 自动粘贴——而 snapOCR 从不
// capture 目标，译文会被粘进 tracker 上一次划词/听写的 App（跨 App 注入）。
@Test @MainActor func translatePreview_rendersCardWithoutTouchingHost() async throws {
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter,
        translator: MockTextTranslationAPI(
            result: TranslationResult(text: "screenshot text", original: "截图文字", targetLanguage: "en-US")))

    await vm.processText("截图文字", outputMode: .translatePreview)

    #expect(inserter.inserted.isEmpty)        // host untouched
    #expect(vm.captureResult?.insertText == "screenshot text")   // card still renders
    #expect(vm.phase == .review)
    #expect(vm.result?.idiomatic == "screenshot text")
}

// 实时 ASR partial 只更新 capsule 预览，不再直接敲进宿主字段。CGEvent 的
// delete/retype 无法证明目标 app 真的完成 cleanup，长句会明显抖动；最终只插
// speech.stop() 返回的 enforced transcript。
@Test @MainActor func rawStreaming_previewsPartialsAndInsertsFinalOnce() async throws {
    let speech = PartialMockSpeechCaptureService()
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: inserter)

    await vm.toggle(outputMode: .rawTranscript)
    speech.emitPartial("今天测试 qwen3 asr")
    try await waitUntil("partial 更新浮窗预览") { vm.transcript == "今天测试 qwen3 asr" }

    speech.transcriptToReturn = "今天测试 Qwen3-ASR"   // hub 的 hard-match 修正过的 final
    await vm.toggle(outputMode: .rawTranscript)        // stop

    #expect(inserter.inserted == ["今天测试 Qwen3-ASR"])
}

// 模式门：review/转换类流程的 partial 只进 capsule 预览，绝不敲进宿主字段。
@Test @MainActor func coachStreaming_previewsPartialsWithoutTypingIntoHost() async throws {
    let speech = PartialMockSpeechCaptureService()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(result: ExpressionResult(idiomatic: "ok", original: "x", reasons: [])),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter())

    await vm.toggle(outputMode: .coachRewrite)
    speech.emitPartial("this conclusion not stable")
    try await waitUntil("capsule 预览更新") { vm.transcript == "this conclusion not stable" }
}

// 猎虫① H5 — 选区/OCR 动作的入口守卫是同步的，但失败发生在 async Task 里：
// 若期间用户已开始听写，迟到的 fail() 曾 reset() 掉 live 会话 → 麦克风永远停不下来
// （stopAndProcess 只在 .listening 可达），下一次 start 还会双装 audio tap 崩溃。
@Test @MainActor func failDuringListening_isIgnored_andCaptureCompletes() async throws {
    let (vm, _) = makeHoldVM(
        transcript: "hello",
        result: ExpressionResult(idiomatic: "Hello.", original: "hello", reasons: []))
    vm.push()
    #expect(vm.phase == .listening)

    vm.fail("没有读到选中文本。")   // stale selection failure lands mid-capture

    #expect(vm.phase == .listening)
    #expect(vm.errorMessage == nil)

    await vm.release()
    #expect(vm.phase == .review)   // the live capture was untouched
}

@Test @MainActor func prepareAskAndListenDuringListening_doesNotRestartCapture() async throws {
    let speech = MockSpeechCaptureService()
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter())

    await vm.toggle(outputMode: .rawTranscript)
    #expect(vm.phase == .listening)
    #expect(speech.captureProfiles.count == 1)

    await vm.prepareAskAndListen(context: "《民法典》第577条")   // late ask resolves mid-capture

    #expect(vm.phase == .listening)
    #expect(speech.captureProfiles.count == 1)   // no second startListening
}

@MainActor
private final class PartialMockSpeechCaptureService: SpeechCaptureService, SpeechPartialTranscriptProviding {
    private(set) var captureProfiles: [SpeechCaptureProfile] = []
    var transcriptToReturn = ""
    var partialsToEmitOnStop: [String] = []
    var stopDelayNanos: UInt64 = 0
    let levels: AsyncStream<Float>
    let partialTranscripts: AsyncStream<String>
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let partialContinuation: AsyncStream<String>.Continuation

    init() {
        (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self)
        (partialTranscripts, partialContinuation) = AsyncStream.makeStream(of: String.self)
    }

    func start(locale: CaptureLocale) throws {}
    func stop() async throws -> String {
        for partial in partialsToEmitOnStop {
            partialContinuation.yield(partial)
            await Task.yield()
        }
        if stopDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: stopDelayNanos)
        }
        return transcriptToReturn
    }

    func emitPartial(_ text: String) {
        partialContinuation.yield(text)
    }
}

extension PartialMockSpeechCaptureService: SpeechCaptureProfileConfigurable {
    func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfiles.append(profile)
    }
}

@MainActor
private final class DelayedStopSpeechCaptureService: SpeechCaptureService {
    let levels: AsyncStream<Float> = AsyncStream { continuation in continuation.finish() }
    private var stopContinuation: CheckedContinuation<String, Never>?

    var isStopAwaiting: Bool { stopContinuation != nil }

    func start(locale: CaptureLocale) throws {}

    func stop() async throws -> String {
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
    }

    func finish(_ text: String) {
        stopContinuation?.resume(returning: text)
        stopContinuation = nil
    }
}

// 296: AX-weak hosts (browser/Electron) report no selection, but the popup
// already captured the text — that text must drive scene routing, and the
// router's REAL confidence must come back (was hardcoded 1.0).
@Test @MainActor func evaluateScene_usesPopupTextWhenAXSelectionEmpty() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(result: nil, error: nil),
        store: FileCaptureStore(fileURL: url),
        inserter: MockTextInserter(),
        contextProvider: { ExpressionContext(selectedText: nil) },   // AX-weak host
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))

    // Selection content carrying document heading cues（起诉状/事实与理由）—
    // typical of reading a brief in a browser, where AX sees nothing.
    let scene = try #require(vm.evaluateScene(
        text: "起诉状\n一、事实与理由\n被告拖欠货款，构成违约，应承担违约责任。"))
    #expect(scene.scene != .unknown)   // popup text reached the router (was: AX-empty → unknown)

    // Real-confidence passthrough: cue-free text must NOT come back as a
    // fully-confident classification the way the hardcoded 1.0 did.
    let vague = try #require(vm.evaluateScene(text: "随便写点什么"))
    #expect(vague.confidence < 1.0)
}
