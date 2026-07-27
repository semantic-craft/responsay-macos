import SwiftUI
import Foundation
import ResponsayCore

/// Thin renderer over `ProviderConfigMachine`: this view owns ONLY layout. All the config
/// state, plan→model routing, endpoint picking, keychain reads/writes and the connection
/// probe live in the machine (unit-tested without SwiftUI). The `.onChange` handlers below
/// delegate to machine methods — the same onChange→side-effect mapping as before the extraction.
struct CapabilityCardView: View {
    let capability: ModelCapability
    var preferredProviderId: String?

    @State private var machine: ProviderConfigMachine

    init(capability: ModelCapability, preferredProviderId: String? = nil) {
        self.capability = capability
        self.preferredProviderId = preferredProviderId
        _machine = State(initialValue: ProviderConfigMachine(
            capability: capability, preferredProviderId: preferredProviderId))
    }

    /// Combined-picker selection ⇄ (regionRaw, planRaw). Picking an endpoint sets both, so the
    /// onChange handlers refresh the Base URL and (for Qwen) auto-switch the per-plan model.
    private var endpointSelection: Binding<String> {
        Binding(
            get: { "\(machine.region.rawValue)|\(machine.plan.rawValue)" },
            set: { composite in
                let parts = composite.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                machine.regionRaw = parts[0]
                machine.planRaw = parts[1]
            })
    }

    var body: some View {
        WarmCard {
            CapabilityHeader(systemImage: icon, title: capability.connectionTitle, subtitle: subtitle,
                             searchCapable: machine.current.builtinSearch && !machine.current.isLocal)
            WarmDivider()

            LabeledRow(label: "配置档案") {
                HStack(spacing: 8) {
                    Picker("", selection: $machine.providerId) {
                        ForEach(machine.presets) { Text($0.displayName(for: capability)).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    if machine.endpointChoices.count > 1 {
                        Picker("", selection: endpointSelection) {
                            ForEach(Array(machine.endpointChoices.enumerated()), id: \.offset) { _, e in
                                Text(endpointLabel(e)).tag("\(e.region.rawValue)|\(e.plan.rawValue)")
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }
            }

            credentialRows
            if machine.isFixedEndpoint {
                // 千问极速实时 / 豆包流式 的端点与模型由 WSS 实时流式引擎 hardcode（忽略这里的值），
                // 所以只读展示真实端点+模型，不给可编辑框，免得显示成历史批量配置误导。
                LabeledRow(label: "端点 / 模型") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.baseURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SettingsTheme.ink2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("模型 \(machine.model)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SettingsTheme.ink2)
                        Text("实时流式引擎，端点与模型固定、无需配置；首次识别时自动验证服务端。")
                            .font(SettingsTheme.footnote)
                            .foregroundStyle(SettingsTheme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                LabeledRow(label: "Base URL") { WarmField(placeholder: "https://…/v1", text: $machine.baseURL) }
                LabeledRow(label: "模型 ID") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            WarmField(placeholder: "model-name", text: $machine.model)
                            let presetList = machine.current.presetModels[capability] ?? []
                            let menuModels: [String] = {
                                if machine.fetchedModels.isEmpty { return presetList }
                                var combined = presetList
                                for m in machine.fetchedModels where !combined.contains(m) { combined.append(m) }
                                return combined
                            }()
                            if !menuModels.isEmpty {
                                Menu(machine.fetchedModels.isEmpty ? "可选 \(menuModels.count)" : "拉取 \(machine.fetchedModels.count)") {
                                    ForEach(menuModels, id: \.self) { name in
                                        Button(name) { machine.model = name }
                                    }
                                }
                                .frame(width: 110)
                            }
                        }
                        // 兜底：列表只是便捷选项，运行时用的就是这个文本框里的值。任何该服务支持的
                        // 模型 ID 直接手输即可调用，不必出现在预设或「拉取」结果里。
                        Text("不在列表里也行：直接输入该服务支持的任意模型 ID 即可调用。")
                            .font(SettingsTheme.footnote)
                            .foregroundStyle(SettingsTheme.ink3)
                    }
                }
            }
            if capability == .tts {
                LabeledRow(label: "音色") {
                    HStack(spacing: 8) {
                        WarmField(placeholder: "输入或选择音色 ID", text: $machine.voice)
                        let presetList = machine.current.presetVoices
                        if !presetList.isEmpty {
                            Menu("可选 \(presetList.count)") {
                                ForEach(presetList) { v in
                                    Button(v.displayName) { machine.voice = v.id }
                                }
                            }
                            .frame(width: 110)
                        }
                    }
                }
            }
            if !machine.isFixedEndpoint {
                LabeledRow(label: "连接校验") {
                    HStack(spacing: 8) {
                        Button("验证") { machine.probe(fetch: false) }.controlSize(.small)
                        Button("拉取模型") { machine.probe(fetch: true) }.controlSize(.small)
                        if !machine.status.isEmpty {
                            Text(machine.status).font(SettingsTheme.footnote).foregroundStyle(statusColor)
                        }
                    }
                }
            }
        }
        // 朗读 only: the active `byok.tts.provider` is what tells `TTSEngine.selected` a cloud
        // voice is configured, and nothing else writes it from this card. ASR / LLM are excluded
        // on purpose — their active provider is written in lockstep with the engine enum by the
        // model-route picker, so writing it here alone would desync `asrEngine` from its config.
        .onAppear {
            machine.load()
            guard capability == .tts else { return }
            TTSActiveProvider.adoptShownProviderIfUnset(
                machine.providerId,
                hasCredential: machine.hasStoredCredential,
                defaults: machine.defaults)
        }
        .onChange(of: machine.providerId) { _, _ in
            machine.selectProvider()
            guard capability == .tts else { return }
            TTSActiveProvider.adopt(machine.providerId, defaults: machine.defaults)
        }
        .onChange(of: machine.regionRaw) { _, _ in machine.baseURL = machine.endpointBase(); machine.persist() }
        .onChange(of: machine.planRaw) { old, new in
            machine.autoSwitchModel(from: old, to: new)
            machine.baseURL = machine.endpointBase()
            machine.reloadKeyForCurrentPlan()
            machine.persist()
        }
        .onChange(of: machine.model) { _, _ in machine.persist() }
        .onChange(of: machine.voice) { _, _ in machine.persist() }
        .onChange(of: machine.baseURL) { _, _ in machine.persist() }
        .onChange(of: machine.apiKey) { _, _ in machine.writeApiKey() }
        .onChange(of: machine.appId) { _, _ in machine.writeAppId() }
        .onChange(of: machine.accessToken) { _, _ in machine.writeAccessToken() }
        .onChange(of: machine.boostingTableId) { _, _ in machine.writeBoostingTableId() }
    }

    @ViewBuilder private var credentialRows: some View {
        switch machine.current.credentialShape {
        case .apiKey:
            LabeledRow(label: "\(keyLabel)") { SecureKeyField(placeholder: "粘贴你的密钥", text: $machine.apiKey) }
            if machine.current.isCustom, capability == .asr {
                LabeledRow(label: "") {
                    Text("Base URL 填到 …/v1 为止（如 https://your-host/v1），请求会自动追加 /audio/transcriptions；模型名如 whisper-large-v3。")
                        .font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let hint = machine.current.keyFormatHint(for: capability) {
                LabeledRow(label: "") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("格式 \(hint) · 存系统钥匙串")
                            .font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink3)
                    }
                }
            }
        case .appIdAndToken:
            LabeledRow(label: "APP ID") { SecureKeyField(placeholder: "填写应用 APP ID", text: $machine.appId) }
            LabeledRow(label: "Access Token") { SecureKeyField(placeholder: "填写 Access Token", text: $machine.accessToken) }
            if capability == .asr {
                LabeledRow(label: "热词词表 ID") { TextField("选填：控制台「自学习平台 › 热词管理」的词表 ID", text: $machine.boostingTableId).textFieldStyle(.roundedBorder) }
            }
            LabeledRow(label: "") {
                VStack(alignment: .leading, spacing: 4) {
                    if let hint = machine.current.keyFormatHint(for: capability) {
                        Text("格式 \(hint) · 存系统钥匙串")
                            .font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink3)
                    }
                    if capability == .asr {
                        Text("不填词表时自动注入应用内「识别词典」做热词纠偏；填了词表则以控制台词表为准（官方限制：单次识别只生效一种）。")
                            .font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Presentation

    private var icon: String {
        switch capability {
        case .asr: "waveform"
        case .llm: "sparkles"
        case .tts: "speaker.wave.2"
        }
    }
    private var subtitle: LocalizedStringKey {
        switch capability {
        case .asr: "这里只管理当前云端识别档案的密钥、端点和模型 ID；实际使用哪一路在上方选择。"
        case .llm: "这里只管理当前文本模型档案的密钥、端点和模型 ID。"
        case .tts: "这里只管理当前云端朗读档案的密钥、端点、模型 ID 和音色。"
        }
    }
    private var keyLabel: String { machine.current.keyLabel.isEmpty ? "API Key" : machine.current.keyLabel }
    private var statusColor: Color { machine.status.hasPrefix("✓") ? SettingsTheme.green : SettingsTheme.ink2 }
    /// Label for one endpoint in the combined 接入点 picker. Append the plan only where the
    /// region offers more than one (国内·按量付费 / 国内·Token Plan); single-plan regions stay
    /// plain (新加坡 / 欧洲).
    private func endpointLabel(_ e: EndpointVariant) -> String {
        let plansInRegion = Set(machine.current.endpoints(for: capability)
            .filter { $0.region == e.region && !$0.baseURL.isEmpty }
            .map(\.plan))
        return plansInRegion.count > 1 ? "\(e.region.label)·\(e.plan.label)" : e.region.label
    }
}
