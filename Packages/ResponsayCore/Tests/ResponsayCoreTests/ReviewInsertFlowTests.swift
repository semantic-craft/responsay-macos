import Testing
import Foundation
@testable import ResponsayCore

@MainActor
private func makeVM(transcript: String, result: ExpressionResult? = nil, expressError: CoachAPIError? = nil)
    -> (QuickCaptureViewModel, MockTextInserter, FileCaptureStore) {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = transcript
    let coach = MockCoachAPI(result: result, error: expressError)
    let inserter = MockTextInserter()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = FileCaptureStore(fileURL: url)
    return (QuickCaptureViewModel(speech: speech, coach: coach, store: store, inserter: inserter), inserter, store)
}

@MainActor
private func makeReviewReadyVM(
    idiomatic: String,
    alternatives: [String] = [],
    original: String = "i want send file",
    inserter: MockTextInserter = MockTextInserter()
) async -> QuickCaptureViewModel {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = original
    let coach = MockCoachAPI(result: ExpressionResult(
        idiomatic: idiomatic, original: original, reasons: [], alternatives: alternatives))
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = FileCaptureStore(fileURL: url)
    let vm = QuickCaptureViewModel(speech: speech, coach: coach, store: store, inserter: inserter)
    await vm.toggle(); await vm.toggle()          // idle -> listening -> review
    return vm
}

@Test @MainActor func active_idiomatic_defaults_to_result_then_follows_selection() async {
    let vm = await makeReviewReadyVM(idiomatic: "Could you send the file?",
                                     alternatives: ["Mind sending the file?"])
    #expect(vm.activeIdiomatic == "Could you send the file?")
    vm.selectAlternative("Mind sending the file?")
    #expect(vm.activeIdiomatic == "Mind sending the file?")
    vm.selectIdiomatic()
    #expect(vm.activeIdiomatic == "Could you send the file?")
}

@Test @MainActor func confirmInsert_inserts_active_sentence_not_just_idiomatic() async {
    let inserter = MockTextInserter()
    let vm = await makeReviewReadyVM(idiomatic: "Could you send the file?",
                                     alternatives: ["Mind sending the file?"],
                                     inserter: inserter)
    vm.selectAlternative("Mind sending the file?")
    await vm.confirmInsert()
    #expect(inserter.inserted == ["Mind sending the file?"])
}

@Test @MainActor func toggle_startsThenStops_landsInReview_andSaves() async throws {
    let (vm, ins, store) = makeVM(
        transcript: "i want fix bug",
        result: ExpressionResult(idiomatic: "I want to fix the bug.", original: "i want fix bug", reasons: ["缺 to"]))
    await vm.toggle()                             // idle -> listening
    #expect(vm.phase == .listening)
    await vm.toggle()                             // listening -> stop -> express -> review
    #expect(vm.phase == .review)
    #expect(vm.result?.idiomatic == "I want to fix the bug.")
    #expect(try store.recent(10).first?.idiomatic == "I want to fix the bug.")  // 出结果即入库
    #expect(ins.inserted.isEmpty)                 // 还没插入
}

@Test @MainActor func confirmInsert_insertsIdiomatic_thenIdle() async throws {
    let (vm, ins, _) = makeVM(
        transcript: "hi", result: ExpressionResult(idiomatic: "Hello.", original: "hi", reasons: []))
    await vm.toggle(); await vm.toggle()
    await vm.confirmInsert()
    #expect(ins.inserted == ["Hello."])
    #expect(vm.phase == .idle)
}

@Test @MainActor func rawTranscriptMode_insertsOriginal_withoutCoach() async throws {
    let (vm, ins, store) = makeVM(transcript: "你好，我想修复这个 bug", expressError: .message("backend down"))
    await vm.toggle(outputMode: .rawTranscript)
    await vm.toggle(outputMode: .rawTranscript)
    #expect(vm.phase == .idle)
    #expect(vm.transcript == "你好，我想修复这个 bug")
    #expect(vm.result == nil)
    #expect(ins.inserted == ["你好，我想修复这个 bug"])
    #expect(try store.recent(10).first?.idiomatic == "你好，我想修复这个 bug")
    }

    @Test @MainActor func polishedTranscriptMode_usesPolishRoute_withoutCoach() async throws {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "你好 我想修复这个 bug"
        let coach = MockCoachAPI(result: nil, error: .message("coach should not run"))
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let polisher = MockTextPolishAPI(result: PolishResult(
            text: "你好，我想修复这个 bug。",
            original: "你好 我想修复这个 bug",
            changes: ["补齐中文标点。"]))
        let vm = QuickCaptureViewModel(
            speech: speech,
            coach: coach,
            store: store,
            inserter: inserter,
            polisher: polisher)

        await vm.toggle(outputMode: .polishedTranscript)
        await vm.toggle(outputMode: .polishedTranscript)

        #expect(vm.phase == .idle)
        #expect(vm.result == nil)
        #expect(inserter.inserted == ["你好，我想修复这个 bug。"])
        #expect(try store.recent(10).first?.reasons == ["补齐中文标点。"])
    }

    @Test @MainActor func selectedTextTranslateMode_insertsTranslation_withoutCoachReview() async throws {
        let speech = MockSpeechCaptureService()
        let coach = MockCoachAPI(result: nil, error: .message("coach should not run"))
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let translator = MockTextTranslationAPI(result: TranslationResult(
            text: "Let me check.",
            original: "我看看",
            targetLanguage: TranslationTargetLanguage.englishUS.rawValue,
            notes: ["meaning-first"]))
        let vm = QuickCaptureViewModel(
            speech: speech,
            coach: coach,
            store: store,
            inserter: inserter,
            translator: translator,
            // 划词翻译 is auto-direction: it must use the 第一/第二语言 pair resolver, NOT the fixed
            // 听写 target. Set the fixed target to .german so the assertion proves the auto resolver
            // (Chinese input + 第一=中文 → 第二=英语) drove it, not the fixed provider.
            translationTargetProvider: { .german },
            snapTranslationTargetResolver: {
                SnapTranslateTarget.auto.resolved(for: $0, primary: .chineseSimplified, secondary: .englishUS)
            })

        await vm.processText("我看看", outputMode: .translateWritten)

        #expect(vm.phase == .idle)
        #expect(vm.result == nil)
        #expect(inserter.inserted == ["Let me check."])
        #expect(try store.recent(10).first?.language == "translate:en-US")
    }

@Test @MainActor func rawTranscriptMode_emptyTranscript_returnsIdle() async throws {
    let (vm, ins, store) = makeVM(transcript: "   ")
    await vm.toggle(outputMode: .rawTranscript)
    await vm.toggle(outputMode: .rawTranscript)
    #expect(vm.phase == .idle)
    #expect(ins.inserted.isEmpty)
    #expect(try store.recent(10).isEmpty)
}


@Test @MainActor func teachingMode_expressesThenAutoInsertsAndReviews() async throws {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = "i want fix bug"
    let result = ExpressionResult(
        idiomatic: "I want to fix the bug.",
        original: "i want fix bug",
        reasons: ["缺少 to。"])
    let coach = MockCoachAPI(result: result, error: nil)
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(speech: speech, coach: coach, store: store, inserter: inserter)

    await vm.toggle(outputMode: .teachingFeedback)
    await vm.toggle(outputMode: .teachingFeedback)

    #expect(vm.phase == .review)
    #expect(vm.didAutoInsertResult)
    #expect(inserter.inserted == ["I want to fix the bug."])
    #expect(vm.captureResult?.mode == .expressInEnglish)
    #expect(vm.captureResult?.insertText == "I want to fix the bug.")
    #expect(vm.captureResult?.sidecarPolicy == .autoOpenCoach)
    #expect(vm.result?.idiomatic == "I want to fix the bug.")
    #expect(vm.result?.reasons.contains("缺少 to。") == true)
}

@Test @MainActor func discard_doesNotInsert_returnsIdle() async throws {
    let (vm, ins, _) = makeVM(
        transcript: "hi", result: ExpressionResult(idiomatic: "Hello.", original: "hi", reasons: []))
    await vm.toggle(); await vm.toggle()
    vm.discard()
    #expect(ins.inserted.isEmpty)
    #expect(vm.phase == .idle)
}

@Test @MainActor func emptyTranscript_returnsToIdle() async throws {
    let (vm, ins, store) = makeVM(transcript: "   ")
    await vm.toggle(); await vm.toggle()
    #expect(vm.phase == .idle)
    #expect(ins.inserted.isEmpty)
    #expect(try store.recent(10).isEmpty)
}

@Test @MainActor func expressFails_setsError_butPreservesRecognizedTranscript() async throws {
    // A failed LLM transform must NOT discard a correctly-recognized transcript: it shows
    // the error AND persists the raw text to history, so it's never lost (openless keeps
    // every session). Nothing is inserted (cross-language fail → no auto-insert of raw).
    let (vm, ins, store) = makeVM(transcript: "hello", expressError: .message("backend down"))
    await vm.toggle(); await vm.toggle()
    #expect(vm.phase == .error)
    #expect(vm.errorMessage?.isEmpty == false)
    #expect(ins.inserted.isEmpty)
    let saved = try store.recent(10)
    #expect(saved.count == 1)
    #expect(saved.first?.sourceText == "hello")
}

@Test @MainActor func processText_landsInReview_andSaves() async throws {
    let (vm, ins, store) = makeVM(
        transcript: "",
        result: ExpressionResult(
            idiomatic: "I'd like to fix this bug.",
            original: "I want fix this bug.",
            reasons: ["补上 to，并把表达改成更自然的 I'd like to。"]))
    await vm.processText("I want fix this bug.")
    #expect(vm.phase == .review)
    #expect(vm.transcript == "I want fix this bug.")
    #expect(vm.result?.idiomatic == "I'd like to fix this bug.")
    #expect(try store.recent(10).first?.sourceText == "I want fix this bug.")
    #expect(ins.inserted.isEmpty)
}

@Test @MainActor func processText_ignoresWhileListening() async throws {
    let (vm, _, _) = makeVM(transcript: "speech")
    await vm.toggle()
    await vm.processText("selected text")
    #expect(vm.phase == .listening)
    #expect(vm.transcript.isEmpty)
}

@Test @MainActor func consumesLevels_whileListening() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "x"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let vm = QuickCaptureViewModel(speech: speech, coach: MockCoachAPI(result: nil, error: nil),
                                   store: FileCaptureStore(fileURL: url), inserter: MockTextInserter())
    await vm.toggle()
    speech.emitLevel(0.6)
    try await waitUntil("levelTask 消费到电平值") { vm.level > 0 }
    #expect(vm.level > 0)
}
