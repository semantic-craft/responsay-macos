import Testing
import Foundation
@testable import ResponsayCore

// 任意提问 (Ask Anything) reuses the Global Voice Assistant as the open-chat
// engine. The only selection-specific logic is: turn one is grounded in the
// selection via the `<selected_text>` envelope, later turns are bare (selection
// rides history), and the system prompt switches to the selection one.
// `apiMessages` is the pure seam that owns this, tested without network/audio.

@Suite struct VoiceAssistantSelectionAskTests {
    @Test func apiMessages_envelopesOnlyFirstUserTurnWithSelection() {
        let msgs = [
            VoiceAssistantMessage(role: "user", content: "核心主张是什么？"),
            VoiceAssistantMessage(role: "assistant", content: "它主张违约。"),
            VoiceAssistantMessage(role: "user", content: "那责任呢？"),
        ]
        let api = VoiceAssistantViewModel.apiMessages(
            systemPrompt: SelectionAskEnvelope.systemPrompt(),
            messages: msgs,
            selection: "The defendant breached the contract.")

        #expect(api.first?["role"] == "system")
        #expect(api.first?["content"]?.contains("selected_text") == true)
        // First user turn carries the selection envelope.
        #expect(api[1]["content"]?.contains("<selected_text>") == true)
        #expect(api[1]["content"]?.contains("核心主张是什么？") == true)
        // Assistant passes through untouched.
        #expect(api[2]["content"] == "它主张违约。")
        // Second user turn is bare — selection rides the history, never re-sent.
        #expect(api[3]["content"] == "那责任呢？")
    }

    @Test func apiMessages_noSelectionPreservesGlobalAssistantShape() {
        let msgs = [VoiceAssistantMessage(role: "user", content: "hi")]
        let api = VoiceAssistantViewModel.apiMessages(
            systemPrompt: VoiceAssistantViewModel.defaultSystemPrompt,
            messages: msgs,
            selection: nil)
        #expect(api == [
            ["role": "system", "content": VoiceAssistantViewModel.defaultSystemPrompt],
            ["role": "user", "content": "hi"],
        ])
    }

    @MainActor @Test func beginSelectionAsk_setsContextAndClearResets() {
        let vm = VoiceAssistantViewModel(speech: MockSpeechCaptureService())
        vm.beginSelectionAsk(selection: "Some selected paragraph.")
        #expect(vm.selectionContext == "Some selected paragraph.")
        vm.clearConversation()
        #expect(vm.selectionContext == nil)
    }

    // 任意提问 from a hotkey starts the mic FIRST (so the first words aren't clipped),
    // then grounds on the selection grabbed concurrently — `attachSelection` is that
    // non-resetting seam (vs `beginSelectionAsk`, which clears the conversation).
    @MainActor @Test func attachSelection_groundsWithoutResetting() {
        let vm = VoiceAssistantViewModel(speech: MockSpeechCaptureService())
        vm.attachSelection("Some selected paragraph.")
        #expect(vm.selectionContext == "Some selected paragraph.")
    }

    // Once a selection is attached (or seeded), a later concurrent grab must not
    // overwrite it — the first ground wins, so a stale read can't re-ground mid-session.
    @MainActor @Test func attachSelection_doesNotOverwriteExistingGround() {
        let vm = VoiceAssistantViewModel(speech: MockSpeechCaptureService())
        vm.beginSelectionAsk(selection: "first")
        vm.attachSelection("second")
        #expect(vm.selectionContext == "first")
    }

    // Empty / whitespace selection → plain global 任意提问 (no fabricated ground).
    @MainActor @Test func attachSelection_ignoresEmptySelection() {
        let vm = VoiceAssistantViewModel(speech: MockSpeechCaptureService())
        vm.attachSelection("   \n  ")
        #expect(vm.selectionContext == nil)
    }

    // Privacy cap applies to the hotkey-grabbed selection too (same as beginSelectionAsk).
    @MainActor @Test func attachSelection_truncatesOverLimit() {
        let vm = VoiceAssistantViewModel(speech: MockSpeechCaptureService())
        vm.attachSelection(String(repeating: "字", count: SelectionAskPolicy.defaultLimit + 50))
        #expect(vm.selectionContext?.count == SelectionAskPolicy.defaultLimit)
    }
}
