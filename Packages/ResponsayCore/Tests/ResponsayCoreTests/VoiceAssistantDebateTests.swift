import Testing
@testable import ResponsayCore

/// Records the system prompt of each stream call, then yields a canned answer so the
/// multi-turn 对抗 progression can be observed turn by turn.
private final class CapturingChatClient: StreamingChatClient, @unchecked Sendable {
    private(set) var systemPrompts: [String] = []
    func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        systemPrompts.append(messages.first { $0["role"] == "system" }?["content"] ?? "")
        return AsyncThrowingStream { c in
            c.yield(.delta("ok")); c.yield(.done); c.finish()
        }
    }
}

@Suite @MainActor struct VoiceAssistantDebateTests {

    private func turn(_ vm: VoiceAssistantViewModel, _ speech: MockSpeechCaptureService,
                      _ text: String, _ client: CapturingChatClient) async {
        speech.transcriptToReturn = text
        vm.startCapture()
        await vm.stopCapture(client: client)
        await vm.awaitResponseCompletion()
    }

    /// 技能卡片已充当首轮论证重构，所以对话一进来就是审稿人加压——没有单独的蓝图轮。
    @Test("首轮：对抗模式下系统提示 = 审稿人加压指令")
    func firstTurnUsesReviewerPressureDirective() async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = CapturingChatClient()
        vm.beginDebate(subject: "本文主张平台责任应以过错为限……", script: .counterargument)
        await turn(vm, speech, "来挑毛病", client)
        #expect(client.systemPrompts.first == DebateStance.pressure.directive(.counterargument))
    }

    @Test("多轮推进：审稿人加压 → 作者回应 → 审稿人加压")
    func turnsAdvanceThroughStances() async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = CapturingChatClient()
        vm.beginDebate(subject: "论点……", script: .counterargument)
        await turn(vm, speech, "开始", client)
        await turn(vm, speech, "继续", client)
        await turn(vm, speech, "继续", client)
        #expect(client.systemPrompts == [
            DebateStance.pressure.directive(.counterargument),
            DebateStance.reply.directive(.counterargument),
            DebateStance.pressure.directive(.counterargument),
        ])
    }

    @Test("非对抗模式不受影响：普通任意提问仍用默认 persona")
    func nonDebateUsesDefaultPersona() async {
        let speech = MockSpeechCaptureService()
        let vm = VoiceAssistantViewModel(speech: speech)
        let client = CapturingChatClient()
        await turn(vm, speech, "今天天气如何", client)
        #expect(client.systemPrompts.first == VoiceAssistantViewModel.defaultSystemPrompt)
    }
}
