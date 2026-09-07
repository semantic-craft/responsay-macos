import Testing
@testable import ResponsayCore

@Suite @MainActor struct VoiceAssistantCaptureLifetimeTests {
    @Test func selectionAskCannotHideAnActiveMicrophone() async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.attachSelection("original")
        vm.startCapture()
        vm.beginSelectionAsk(selection: "replacement")
        #expect(vm.phase == .listening)
        #expect(vm.selectionContext == "original")
        await vm.cancelCapture()
        #expect(speech.stopCalls == 1)
        vm.startCapture()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
    }

    @Test(arguments: DebateScript.allCases)
    func debateCannotHideAnActiveMicrophone(script: DebateScript) async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.startCapture()
        vm.beginDebate(subject: "replacement", script: script)
        #expect(vm.phase == .listening)
        #expect(vm.selectionContext == nil)
        await vm.cancelCapture()
        #expect(speech.stopCalls == 1)
    }

    @Test func directResetCannotHideAnActiveMicrophone() async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.startCapture()
        vm.clearConversation()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
        #expect(speech.stopCalls == 1)
    }
    @Test func deadlineStopsCaptureWithoutAskingAQuestion() async throws {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "discard this question"
        let vm = VoiceAssistantViewModel(speech: speech)
        #expect(vm.maxListeningDuration == .seconds(900))
        vm.maxListeningDuration = .milliseconds(10)
        vm.startCapture()
        // This checks expiry behavior, not scheduler latency: the full CI suite can
        // occupy MainActor for several seconds before the 10 ms timer resumes.
        let deadline = ContinuousClock.now + .seconds(30)
        while vm.phase != .idle, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(vm.phase == .idle)
        #expect(speech.stopCalls == 1)
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage != nil)
        vm.maxListeningDuration = .seconds(60)
        vm.startCapture()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
    }

    @Test(arguments: [true, false])
    func stoppedSessionDeadlineCannotStopNextCapture(cancel: Bool) async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.maxListeningDuration = .milliseconds(30)
        vm.startCapture()
        await Task.yield()
        if cancel { await vm.cancelCapture() }
        else { await vm.stopCapture(client: nil) }
        vm.maxListeningDuration = .seconds(60)
        vm.startCapture()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.phase == .listening)
        #expect(speech.stopCalls == 1)
        await vm.cancelCapture()
    }

    @Test func oldAnswerCannotHideNewRecording() async {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "question"
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = HeldAnswerClient()
        vm.startCapture()
        await vm.stopCapture(client: client)
        #expect(vm.phase == .responding)
        for await _ in client.started { break }
        vm.startCapture()
        client.continuation.finish()
        await vm.awaitResponseCompletion()
        #expect(vm.phase == .listening)
        await vm.cancelCapture()
        #expect(speech.stopCalls == 2)
    }

    @Test func failedFollowUpStartPreservesStreamingAnswer() async {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "question"
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = HeldAnswerClient()
        vm.startCapture()
        await vm.stopCapture(client: client)
        for await _ in client.started { break }
        speech.startError = CaptureStartFailure()
        vm.startCapture()
        #expect(vm.phase == .responding)
        client.continuation.yield(.delta("complete answer"))
        client.continuation.finish()
        await vm.awaitResponseCompletion()
        #expect(vm.messages.last?.content == "complete answer")
        #expect(vm.errorMessage != nil)
    }

    @Test func cancellingReservesCaptureUntilStopCompletes() async throws {
        let speech = HeldStopSpeech()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.startCapture()
        let cancel = Task { await vm.cancelCapture() }
        let deadline = ContinuousClock.now + .seconds(2)
        while speech.stopContinuation == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(speech.stopContinuation != nil)
        vm.beginSelectionAsk(selection: "new selection")
        vm.beginDebate(subject: "new debate", script: .counterargument)
        vm.clearConversation()
        vm.startCapture()
        await vm.cancelCapture()
        await vm.stopCapture(client: nil)
        #expect(vm.phase == .thinking)
        #expect(vm.selectionContext == nil)
        #expect(speech.startCalls == 1)
        #expect(speech.stopCalls == 1)
        speech.stopContinuation?.resume(returning: "discard")
        await cancel.value
        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
    }

}


private final class HeldAnswerClient: StreamingChatClient, Sendable {
    let streamValue: AsyncThrowingStream<TextStreamEvent, Error>
    let continuation: AsyncThrowingStream<TextStreamEvent, Error>.Continuation
    let started: AsyncStream<Void>
    let startedContinuation: AsyncStream<Void>.Continuation
    init() {
        (streamValue, continuation) = AsyncThrowingStream.makeStream(of: TextStreamEvent.self)
        (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }
    func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        startedContinuation.yield(())
        startedContinuation.finish()
        return streamValue
    }
}

@MainActor private final class HeldStopSpeech: SpeechCaptureService {
    let levels = AsyncStream<Float> { $0.finish() }
    var stopContinuation: CheckedContinuation<String, Never>?
    var startCalls = 0
    var stopCalls = 0
    func start(locale: CaptureLocale) throws { startCalls += 1 }
    func stop() async throws -> String {
        stopCalls += 1
        return await withCheckedContinuation { stopContinuation = $0 }
    }
}

private struct CaptureStartFailure: Error {}
