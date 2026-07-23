import Testing
@testable import ResponsayCore

/// A scripted streaming chat client: yields the given tokens as deltas, then `.done`, then
/// finishes. Lets tests drive the Voice Assistant's streaming path without a network.
private final class ScriptedChatClient: StreamingChatClient, @unchecked Sendable {
    let tokens: [String]
    init(tokens: [String]) { self.tokens = tokens }

    func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(.delta(token)) }
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

@Suite @MainActor struct VoiceAssistantStreamingTests {
    // Bug (fix/ask-anything-stale-leak, second finding): after an answer finished streaming
    // the VM never returned `phase` from `.responding` to `.idle`, so the answer card's
    // 重新生成 button — enabled only when `phase != .responding` — stayed disabled forever.

    @Test func phaseSettlesToIdleAfterAnswerStreams() async throws {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "hello"
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = ScriptedChatClient(tokens: ["Hi", " there"])

        vm.startCapture()
        await vm.stopCapture(client: client)
        await vm.awaitResponseCompletion()

        #expect(vm.phase == .idle)
        #expect(vm.messages.last?.role == "assistant")
        #expect(vm.messages.last?.content == "Hi there")
    }

    @Test func regenerateReStreamsAfterAnswerHasSettled() async throws {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "hello"
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.makeClient = { ScriptedChatClient(tokens: ["second", " answer"]) }

        vm.startCapture()
        await vm.stopCapture(client: ScriptedChatClient(tokens: ["first"]))
        await vm.awaitResponseCompletion()
        #expect(vm.messages.last?.content == "first")

        // 重新生成: drop the last answer, re-stream a fresh one for the same question.
        await vm.regenerate()
        await vm.awaitResponseCompletion()

        #expect(vm.phase == .idle)
        #expect(vm.messages.last?.content == "second answer")
        // Still one Q + one A — regenerate replaces the answer in place, not appends.
        #expect(vm.messages.count == 2)
    }
}
