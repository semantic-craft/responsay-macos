import Foundation
import Testing
@testable import ResponsayCore

@Suite @MainActor struct CaptureFailurePropagationTests {
    @Test func duplicateAndOldFailuresDoNotEndNewGeneration() async throws {
        let state = SpeechCaptureFailureState()
        let first = state.begin()
        let stream = state.stream
        var cleaned = 0
        state.fail("disconnected", generation: first) { cleaned += 1 }
        state.fail("duplicate", generation: first) { cleaned += 1 }
        var messages = [String]()
        for await message in stream { messages.append(message) }
        #expect(messages == ["disconnected"])
        #expect(cleaned == 1)
        #expect(throws: (any Error).self) { try state.end() }
        _ = state.begin()
        state.fail("old", generation: first) { cleaned += 1 }
        try state.end()
        #expect(cleaned == 1)
    }

    @Test func inputFailureLeavesListeningWithoutInserting() async throws {
        let speech = FailingCapture()
        let inserter = MockTextInserter()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let vm = QuickCaptureViewModel(speech: speech, coach: MockCoachAPI(),
                                      store: FileCaptureStore(fileURL: url), inserter: inserter)
        vm.push()
        speech.fail()
        for _ in 0..<100 where vm.phase == .listening { await Task.yield() }
        #expect(vm.phase == .error)
        #expect(vm.errorMessage == "设备断开")
        #expect(vm.transcript.isEmpty)
        #expect(inserter.inserted.isEmpty)
        #expect(speech.cancelled == 1)
        #expect(speech.stopped == 0)
        vm.push()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
    }

    @Test func assistantFailureDoesNotSubmitQuestionAndCanRestart() async {
        let speech = FailingCapture()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.startCapture()
        speech.fail()
        for _ in 0..<100 where vm.phase == .listening { await Task.yield() }
        #expect(vm.phase == .idle)
        #expect(vm.errorMessage == "设备断开")
        #expect(vm.messages.isEmpty)
        #expect(speech.cancelled == 1)
        #expect(speech.stopped == 0)
        vm.startCapture()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
    }
}

@MainActor private final class FailingCapture: SpeechCaptureService {
    private let state = SpeechCaptureFailureState()
    private var generation = UUID()
    var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
    var captureFailures: AsyncStream<String> { state.stream }
    var cancelled = 0
    var stopped = 0
    func start(locale: CaptureLocale) throws { generation = state.begin() }
    func stop() async throws -> String { stopped += 1; return "must not insert" }
    func cancel() async { cancelled += 1; try? state.end() }
    func fail() { state.fail("设备断开", generation: generation, cleanup: {}) }
}
