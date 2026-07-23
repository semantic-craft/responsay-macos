import Testing
import Foundation
@testable import ResponsayCore

// Revert AI (P0b): a direct dictation insert whose AI output differs from the raw transcript offers
// 「↩ 原文」; tapping it asks the injected reverter to swap the inserted text back to raw.
@MainActor
private func tmpStore() -> FileCaptureStore {
    FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
}

@MainActor private final class RevertSpy {
    var received: RevertableInsertion?
    var calls = 0
}

@Test @MainActor func polishedDictation_offersRevert_andRevertSwapsToRaw() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let spy = RevertSpy()
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        polisher: MockTextPolishAPI(result: PolishResult(text: "今天天气很好。", original: "今天天气很好")),
        reverter: { r in spy.received = r; spy.calls += 1; return true })

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    let offered = try #require(vm.revertableInsertion)
    #expect(offered.polished == "今天天气很好。")   // what we inserted
    #expect(offered.raw == "今天天气很好")          // what the user actually said

    await vm.revertLastInsertion()
    #expect(spy.calls == 1)
    #expect(spy.received?.raw == "今天天气很好")
    #expect(vm.revertableInsertion == nil)          // chip dismisses
}

@Test @MainActor func rawDictation_doesNotOfferRevert_whenTextUnchanged() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "逐字上屏不变"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        reverter: { _ in true })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.revertableInsertion == nil)   // insertText == sourceTranscript → nothing to revert
}

@Test @MainActor func startingANewCapture_clearsTheRevertOffer() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "你好世界"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        polisher: MockTextPolishAPI(result: PolishResult(text: "你好，世界。", original: "你好世界")),
        reverter: { _ in true })

    vm.push(outputMode: .polishedTranscript)
    await vm.release()
    #expect(vm.revertableInsertion != nil)

    vm.push(outputMode: .polishedTranscript)   // a new capture invalidates the stale offer
    #expect(vm.revertableInsertion == nil)
}

@Test @MainActor func noReverter_neverOffersRevert() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "没有 reverter"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        polisher: MockTextPolishAPI(result: PolishResult(text: "没有 reverter。", original: "没有 reverter")))

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.revertableInsertion == nil)   // reverter == nil → feature inert (headless/tests)
}
