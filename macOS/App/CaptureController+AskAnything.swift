import ResponsayCore

@MainActor
extension CaptureController {
    /// Start a 任意提问 session: open the mic, then ground on the current selection via an AX-only
    /// read (never the ⌘C clipboard fallback — it clobbers the clipboard + injects a key mid-record).
    func startAskAnythingSession() {
        guard voiceAssistantVM.phase == .idle || voiceAssistantVM.phase == .responding else { return }
        guard requireTextModel(feature: "任意提问") else { return }
        targetTracker.capture()
        voiceAssistantVM.startCapture()
        guard voiceAssistantVM.phase == .listening else { return }
        log.info("任意提问 listening")
        speechController.playConfiguredStartCue()
        if let selection = contextReader.readContext(from: targetTracker.target).selectedText {
            voiceAssistantVM.attachSelection(selection)
        }
    }

    func stopAskAnythingSession() {
        speechController.playConfiguredStopCue()
        // 联网搜索(opt-in):把这一问路由到一个可联网的专属模型(Qwen/智谱/MiMo),与主对话模型解耦
        // ——主模型不支持联网时也能真搜到(否则被静默退回普通问答、只答到训练截止)。用户拍板:联网
        // 模型直接回答。nil = 没有配好密钥的可联网模型 → 退回普通问答(resolveChat)。
        // 任意提问是开放对话 → 沿用全局 思考 开关(resolveChat/resolveSearch 都是 .chat purpose)。
        let wantSearch = VoiceAssistantWebSearchSettings.isEnabled()
        let searchEndpoint = wantSearch ? LLMEndpointResolver.resolveSearch() : nil
        let endpoint = searchEndpoint ?? LLMEndpointResolver.resolveChat()
        voiceAssistantVM.searchProviderId = searchEndpoint?.providerId
        log.info("任意提问 stop: endpoint \(endpoint == nil ? "NIL — no general LLM" : "resolved", privacy: .public) search=\(searchEndpoint != nil, privacy: .public)")
        let client: (any StreamingChatClient)? = endpoint.map { ep in
            // 豆包/方舟 与 OpenAI 的联网都只在 /responses 上(OpenAI 的 chat-latest/gpt-5.x 在
            // /chat/completions 上根本搜不了)→ 走流式 Responses 客户端;其余(含豆包纯对话、
            // Qwen/智谱/MiMo 的 /chat/completions 联网)走通用流式 chat 客户端。
            if searchEndpoint != nil, ep.providerId == "doubao" || ep.providerId == "openai" {
                return DirectArkResponsesStreamingClient(endpoint: ep, searchEnabled: true)
            }
            return DirectStreamingChatClient(endpoint: ep, searchEnabled: searchEndpoint != nil)
        }
        Task { await voiceAssistantVM.stopCapture(client: client) }
    }

    /// Esc during 任意提问 listening: close the floating session without sending audio to the LLM.
    func cancelAskAnythingSession() async {
        guard voiceAssistantVM.phase == .listening else { return }
        log.info("任意提问 cancel")
        speechController.playConfiguredStopCue()
        await voiceAssistantVM.cancelCapture()
        voiceAssistantVM.clearConversation()
    }
}
