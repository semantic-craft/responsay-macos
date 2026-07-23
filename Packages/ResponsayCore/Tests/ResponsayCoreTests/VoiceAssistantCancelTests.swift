import Testing
@testable import ResponsayCore

@Suite @MainActor struct VoiceAssistantCancelTests {
    @Test func cancelWhileListeningStopsMicWithoutSendingQuestion() async throws {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = "this should not be asked"
        let vm = VoiceAssistantViewModel(speech: speech)

        vm.startCapture()
        #expect(vm.phase == .listening)

        await vm.cancelCapture()

        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
        #expect(vm.partialTranscript == "")
        #expect(speech.stopCalls == 1)
    }

    @Test func cancelThenClearConversationDismissesPriorCardAndSelectionContext() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)

        vm.attachSelection("private selected paragraph")
        speech.transcriptToReturn = "previous private question"
        vm.startCapture()
        await vm.stopCapture(client: nil)
        #expect(vm.messages.isEmpty == false)
        #expect(vm.selectionContext != nil)

        speech.transcriptToReturn = "this should not be asked"
        vm.startCapture()
        #expect(vm.phase == .listening)

        await vm.cancelCapture()
        vm.clearConversation()

        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
        #expect(vm.selectionContext == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.partialTranscript == "")
        #expect(speech.stopCalls == 2)
    }

    @Test func cancelIsNoOpOutsideListening() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)

        await vm.cancelCapture()

        #expect(vm.phase == .idle)
        #expect(speech.stopCalls == 0)
    }

    @Test func emptyStopDiscardsSelectionContextWithoutSendingQuestion() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.attachSelection("private selected text")

        vm.startCapture()
        await vm.stopCapture(client: nil)

        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
        #expect(vm.selectionContext == nil)
        #expect(speech.stopCalls == 1)
    }

    // MARK: - Privacy: an empty stop must NOT resurface the previous conversation.
    // Repro (fix/ask-anything-stale-leak): a completed 任意提问 Q&A lingers in the VM;
    // pressing the hotkey to start then stopping without speaking left `messages` intact
    // and the panel re-revealed the old answer (VoiceAssistantPanel shows the result for
    // `.idle` with non-empty messages). Saying nothing must discard the session entirely.

    @Test func emptyStopClearsPreviousConversationInsteadOfRevealingIt() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)

        // A real prior question lands in the conversation (client nil → no answer streamed,
        // but the user turn is recorded — enough to prove the conversation is non-empty).
        speech.transcriptToReturn = "previous private question"
        vm.startCapture()
        await vm.stopCapture(client: nil)
        #expect(vm.messages.isEmpty == false)

        // Start again, say nothing, stop. The old conversation must be gone, not re-shown.
        speech.transcriptToReturn = ""
        vm.startCapture()
        await vm.stopCapture(client: nil)

        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
        #expect(vm.selectionContext == nil)
        #expect(vm.errorMessage == nil)
        #expect(speech.stopCalls == 2)
    }

    @Test func whitespaceOnlyTranscriptIsDiscardedNotSentAsQuestion() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)

        // ASR occasionally returns whitespace/newlines for silence — that is "said nothing",
        // not a question. It must not become a user turn or hit the LLM.
        speech.transcriptToReturn = "  \n\t "
        vm.startCapture()
        await vm.stopCapture(client: nil)

        #expect(vm.phase == .idle)
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func emptyStopDropsSeededSelectionSoItIsNotLeftOnScreen() async throws {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)

        // 任意提问 grounded in a private text selection, then the user says nothing.
        // The selection chip must not linger — clear the grounding too.
        vm.attachSelection("private selected paragraph")
        #expect(vm.selectionContext != nil)

        vm.startCapture()
        await vm.stopCapture(client: nil)

        #expect(vm.phase == .idle)
        #expect(vm.selectionContext == nil)
        #expect(vm.messages.isEmpty)
    }
}
