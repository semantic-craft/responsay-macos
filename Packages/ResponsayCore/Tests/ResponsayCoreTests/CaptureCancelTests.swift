import Testing
import Foundation
@testable import ResponsayCore

/// STATE-CANCEL-002: an in-flight capture can be aborted without inserting — but only while
/// listening; once it has produced a review result, cancel must not silently discard it.
@Suite @MainActor struct CaptureCancelTests {
    private func makeVM(transcript: String, result: ExpressionResult? = nil)
        -> (QuickCaptureViewModel, MockTextInserter) {
        let speech = MockSpeechCaptureService(); speech.transcriptToReturn = transcript
        let inserter = MockTextInserter()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let vm = QuickCaptureViewModel(
            speech: speech,
            coach: MockCoachAPI(result: result),
            store: FileCaptureStore(fileURL: url),
            inserter: inserter)
        return (vm, inserter)
    }

    @Test func cancelWhileListeningDiscardsAudioAndInsertsNothing() async throws {
        let (vm, inserter) = makeVM(transcript: "this must never be inserted")
        vm.push()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
        #expect(vm.phase == .idle)
        #expect(vm.transcript == "")
        #expect(inserter.inserted.isEmpty)
    }

    @Test func cancelIsNoOpWhenIdle() async throws {
        let (vm, _) = makeVM(transcript: "x")
        #expect(vm.phase == .idle)
        await vm.cancelCapture()
        #expect(vm.phase == .idle)
    }

    @Test func cancelDoesNotDiscardAReviewResult() async throws {
        let (vm, _) = makeVM(
            transcript: "i want fix bug",
            result: ExpressionResult(idiomatic: "I want to fix the bug.", original: "i want fix bug", reasons: ["缺 to"]))
        vm.push()
        await vm.release()
        #expect(vm.phase == .review)
        await vm.cancelCapture()   // guarded to .listening — must be a no-op here
        #expect(vm.phase == .review)
        #expect(vm.result?.idiomatic == "I want to fix the bug.")
    }
}
