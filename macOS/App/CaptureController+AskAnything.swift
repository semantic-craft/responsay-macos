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
        let wantSearch = VoiceAssistantWebSearchSettings.isEnabled()
        // 独立检索服务(豆包搜索 / Perplexity)优先:配了密钥就走「App 先检索、主模型再作答」,
        // 主模型支不支持联网都无所谓。没配 → 落回下面的「模型自带联网」老路。
        if wantSearch, let backend = WebSearchProviderSettings.backend() {
            startBackendSearchAnswer(backend: backend)
            return
        }
        voiceAssistantVM.searchPreflight = nil
        // 联网搜索(opt-in):把这一问路由到一个可联网的专属模型(Qwen/智谱/MiMo),与主对话模型解耦
        // ——主模型不支持联网时也能真搜到(否则被静默退回普通问答、只答到训练截止)。用户拍板:联网
        // 模型直接回答。nil = 没有配好密钥的可联网模型 → 退回普通问答(resolveChat)。
        // 任意提问是开放对话 → 沿用全局 思考 开关(resolveChat/resolveSearch 都是 .chat purpose)。
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

    /// 独立检索服务这一路:App 先用检索服务搜,把结果作为材料交给**主对话模型**作答。
    /// 主模型走普通 `/chat/completions`(searchEnabled=false)——联网这件事已经由检索服务做完了,
    /// 再叠模型自带联网只会重复搜一遍、还搅乱来源。
    private func startBackendSearchAnswer(backend: any WebSearchBackend) {
        let chatEndpoint = LLMEndpointResolver.resolveChat()
        voiceAssistantVM.searchProviderId = backend.kind.rawValue
        // 检索词提炼借主模型跑(提问超过检索服务的长度上限时才会真调用)。
        let runner = WebSearchRunner(
            backend: backend,
            queryAPI: chatEndpoint.map { DirectSearchQueryAPI(endpoint: $0) })
        voiceAssistantVM.searchPreflight = { [weak self] question in
            do {
                let context = try await runner.context(for: question)
                // 真搜到了才署名:一条没搜到时答案并没有联网材料支撑,答案卡不该挂「联网搜索」。
                // (重新生成会重跑这一段,所以每轮都要重新判定,不能只在失败时撤。)
                self?.voiceAssistantVM.searchProviderId = context == nil ? nil : backend.kind.rawValue
                return context
            } catch {
                // 检索失败(密钥无效 / 额度用尽 / 网络):照常作答,但撤掉署名——
                // 不能让胶囊显示「联网搜索 · 豆包搜索」而实际上一条都没搜到。
                self?.voiceAssistantVM.searchProviderId = nil
                self?.log.error("任意提问 检索失败: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        log.info("任意提问 stop: 检索服务 \(backend.kind.rawValue, privacy: .public) endpoint \(chatEndpoint == nil ? "NIL" : "resolved", privacy: .public)")
        let client = chatEndpoint.map { DirectStreamingChatClient(endpoint: $0, searchEnabled: false) }
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
