import Foundation
import ResponsayCore

/// Connection-check logic for `ProviderConfigMachine`: the 「连接校验」 Validate / Fetch
/// buttons. Split out so the network I/O lives apart from the state/routing.
extension ProviderConfigMachine {
    // MARK: Validate / Fetch

    /// Fetch normally uses `GET <base>/models`; fixed-model providers use local preset validation.
    /// LLM Validate sends one tiny real chat call.
    func probe(fetch: Bool) {
        if !fetch, capability == .llm { validateLLM(); return }
        guard !baseURL.isEmpty else { status = "请先填 Base URL"; return }
        if !CapabilityProbeRequestBuilder.supportsRemoteModelsRequest(
            providerId: providerId,
            capability: capability
        ) {
            validatePresetOnly(fetch: fetch)
            return
        }
        if baseURL.hasPrefix("ws://") || baseURL.hasPrefix("wss://") {
            status = CapabilityProbeMessages.websocketStatus(
                fetch: fetch, providerId: providerId, capability: capability,
                appId: appId, accessToken: accessToken, model: model)
            return
        }

        guard let req = CapabilityProbeRequestBuilder.modelsRequest(
            providerId: providerId,
            capability: capability,
            baseURL: baseURL,
            apiKey: apiKey
        ) else {
            status = "URL 无效"; return
        }
        let isGemini = ProviderModelList.isGeminiBase(baseURL)
        let isASR = capability == .asr
        let activePreset = current
        status = fetch ? "拉取中…" : "校验中…"
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                var msg = code == 200 ? "✓ 已连接" : "HTTP \(code)"
                var models: [String] = []
                if fetch, code == 200 {
                    let all = ProviderModelList.parse(data, isGemini: isGemini)
                    models = LLMModelPresetFilter.models(
                        from: isASR ? ProviderModelList.asrModels(from: all) : all,
                        preset: activePreset, capability: capability)
                    msg = models.isEmpty ? "✓ 已连接（未解析到模型）" : "✓ 拉到 \(models.count) 个模型，点选"
                }
                await MainActor.run {
                    status = msg
                    if fetch { fetchedModels = models }
                }
            } catch {
                await MainActor.run { status = "连接失败" }
            }
        }
    }

    func validatePresetOnly(fetch: Bool) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil
        else {
            status = "URL 无效"
            return
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请先填密钥"
            return
        }

        let models = current.presetModels[capability]
            ?? current.defaultModels[capability].map { [$0] }
            ?? []
        if fetch {
            fetchedModels = models
            status = models.isEmpty ? "✓ 配置格式有效" : "✓ 使用官方模型 \(models.count) 个，点选"
        } else {
            status = "✓ 配置格式有效 · 首次识别时验证服务端"
        }
    }

    /// LLM Validate (240): one tiny real chat completion through the App-direct path.
    /// 技能平台模型与听写模型不同时，两个模型各发一次真实探针 —— 只探默认模型会让另一个
    /// 选择拿到虚假的「可用」状态（例如该模型不支持当前提供商的 Responses API）。
    func validateLLM() {
        let dictation = LLMEndpoint(providerId: providerId, baseURL: baseURL, model: model,
                                    apiKey: apiKey, thinkingEnabled: false)
        guard dictation.isConfigured else { status = "请先填 Base URL / Model / 密钥"; return }
        let skillModelTrimmed = skillModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillEndpoint: LLMEndpoint? = skillModelTrimmed.isEmpty || skillModelTrimmed == model
            ? nil
            : LLMEndpoint(providerId: providerId, baseURL: baseURL, model: skillModelTrimmed,
                          apiKey: apiKey, thinkingEnabled: false)
        status = "校验中…"
        Task {
            do {
                _ = try await LLMConnectivityCheck.validate(endpoint: dictation)
            } catch let error as LLMError {
                let message = CapabilityProbeMessages.llmValidationStatus(error)
                await MainActor.run { status = skillEndpoint == nil ? message : "听写模型：\(message)" }
                return
            } catch {
                await MainActor.run { status = "连接失败" }
                return
            }
            guard let skillEndpoint else {
                await MainActor.run { status = "✓ 已连接 · 模型可用" }
                return
            }
            do {
                _ = try await LLMConnectivityCheck.validate(endpoint: skillEndpoint)
                await MainActor.run { status = "✓ 已连接 · 听写与技能平台模型均可用" }
            } catch let error as LLMError {
                let message = CapabilityProbeMessages.llmValidationStatus(error)
                await MainActor.run { status = "听写模型可用；技能平台模型不可用：\(message)" }
            } catch {
                await MainActor.run { status = "听写模型可用；技能平台模型连接失败" }
            }
        }
    }
}
