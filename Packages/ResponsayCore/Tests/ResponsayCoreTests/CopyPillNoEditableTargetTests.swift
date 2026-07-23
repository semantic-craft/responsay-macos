import Testing
import Foundation
@testable import ResponsayCore

// 复制弹窗 parity: when there is no editable target, a dictation result is offered as a copy pill
// (`.copied`) instead of being pasted into the void — so a dictation made with the cursor outside
// any field isn't lost. The decision is driven by the injected `isEditableTarget` closure.
@MainActor
private func copyPillStore() -> FileCaptureStore {
    FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
}

@Test @MainActor func noEditableTarget_routesDictationToCopyPill_withoutInserting() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: copyPillStore(),
        inserter: inserter,
        polisher: MockTextPolishAPI(result: PolishResult(text: "今天天气很好。", original: "今天天气很好")),
        isEditableTarget: { false })

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.phase == .copied)
    #expect(vm.copiedText == "今天天气很好。")   // the text the user can recover
    #expect(inserter.inserted.isEmpty)          // never pasted ⌘V into the void

    vm.dismissCopied()
    #expect(vm.phase == .idle)
    #expect(vm.copiedText == "")
}

@Test @MainActor func editableTarget_insertsNormally() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: copyPillStore(),
        inserter: inserter,
        polisher: MockTextPolishAPI(result: PolishResult(text: "今天天气很好。", original: "今天天气很好")),
        isEditableTarget: { true })

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.phase == .idle)
    #expect(inserter.inserted == ["今天天气很好。"])
    #expect(vm.copiedText == "")
}

@Test @MainActor func noEditableTargetClosure_insertsNormally() async throws {
    // nil closure (tests/headless) preserves today's behavior — always insert, never a copy pill.
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let inserter = MockTextInserter()
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: copyPillStore(),
        inserter: inserter,
        polisher: MockTextPolishAPI(result: PolishResult(text: "今天天气很好。", original: "今天天气很好")))

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.phase == .idle)
    #expect(inserter.inserted == ["今天天气很好。"])
}
