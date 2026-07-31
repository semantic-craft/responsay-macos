import SwiftUI
import ResponsayCore

/// 378 · 设置·模型 — the single home for "which model is each lane using, and is it
/// configured". Four lanes (语音识别 / 文本改写 / 文本朗读 / 图片识别), each with an inline
/// switcher (writes the same UserDefaults the menu-bar + overview read, via
/// `ModelRouteSelectionActions` / engine raws) and a readiness pill. An unconfigured cloud
/// lane shows a big amber CTA that jumps to that capability's existing config pane. Renders
/// from `ModelLaneDisplay` so it never drifts from the menu-bar / overview surfaces.
struct SettingsModelsPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    // Observed so the rows refresh the instant a selection changes anywhere.
    @AppStorage(ASREngine.defaultsKey) private var asrEngineRaw = ASREngine.selected.rawValue
    @AppStorage(TTSEngine.defaultsKey) private var ttsEngineRaw = TTSEngine.selected.rawValue
    @AppStorage(OCREngine.defaultsKey) private var ocrEngineRaw = OCREngine.selected.rawValue
    @AppStorage("byok.llm.provider") private var llmProviderRaw = ""
    @AppStorage("byok.asr.provider") private var asrProviderRaw = ""
    @AppStorage("byok.tts.provider") private var ttsProviderRaw = ""

    /// Jump to a capability's config section within the settings window.
    let openSection: (SettingsSection) -> Void

    /// Readiness pills are Keychain-backed, so `ModelLaneDisplay().lanes()` does blocking
    /// `BYOKKeychain.read`s. Resolving it on every render froze the panel on selection (the
    /// dropdown "卡在那" bug). Cache it in @State and recompute OFF the main thread on the triggers
    /// below; the picker's current value comes from the cheap `liveCurrentId` (UserDefaults only),
    /// so selection stays instant even before the cache refreshes.
    @State private var lanes: [ModelLaneInfo] = []
    @State private var refreshNonce = 0

    /// Changes whenever any lane's stored selection changes (or the app reactivates), driving a
    /// `.task(id:)` recompute. Pure UserDefaults reads — no Keychain — so it's cheap per render.
    private var reloadKey: String {
        "\(asrEngineRaw)|\(asrProviderRaw)|\(llmProviderRaw)|\(ttsEngineRaw)|\(ttsProviderRaw)|\(ocrEngineRaw)#\(refreshNonce)"
    }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "模型", desc: "四类模型各选一路：语音识别 / 文本改写 / 文本朗读 / 图片识别。")

            SettingsStatusBar {
                StatusDot(state: allReady ? .green : .amber)
                Text(allReady ? "四路模型均已就绪" : "有模型尚未就绪")
                Spacer(minLength: 0)
                Text("当前使用哪一路在这里选；密钥/端点进各自配置页")
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
            WarmCard {
                CapabilityHeader(
                    systemImage: "slider.horizontal.3",
                    title: "模型选择",
                    subtitle: "四类模型各选一路。本机引擎无需密钥；云端模型按需在「配置」里填你的密钥（存本机钥匙串）。")
                WarmDivider()
                ForEach(lanes) { lane in
                    laneRow(lane)
                    if lane.id != lanes.last?.id { WarmDivider() }
                }
            }
        }
        .navigationTitle("模型")
        .task(id: reloadKey) {
            // Resolve Keychain-backed readiness off the main thread; never block render/selection.
            let computed = await Task.detached(priority: .userInitiated) {
                ModelLaneDisplay().lanes()
            }.value
            // A stale task (reloadKey already changed) must not clobber a newer result.
            guard !Task.isCancelled else { return }
            lanes = computed
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNonce &+= 1   // re-resolve Keychain-backed readiness after editing keys elsewhere
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelConfigurationDidChange)) { _ in
            refreshNonce &+= 1
        }
    }

    private var allReady: Bool { lanes.allSatisfy { $0.readiness.isReady } }

    // MARK: - Lane row

    @ViewBuilder
    private func laneRow(_ lane: ModelLaneInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(SettingsTheme.card2)
                    Image(systemName: lane.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.ink2)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(lane.title)
                            .font(SettingsTheme.footnote.weight(.semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        badge(lane.badge)
                    }
                    Text("模型 ID: \(lane.modelId)")
                        .font(.system(size: SkinMetrics.fsCaption))
                        .foregroundStyle(SettingsTheme.ink3)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 10)
                Picker("", selection: optionBinding(for: lane)) {
                    pickerOptions(for: lane)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 230)
                .help(lane.lane == .asr ? "切换语音识别服务" : "切换\(lane.title)模型")
            }
            readinessRow(lane)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func readinessRow(_ lane: ModelLaneInfo) -> some View {
        switch lane.readiness {
        case .local:
            pill(systemImage: "checkmark.circle.fill", text: "本机 · 就绪", color: SettingsTheme.green, bg: SettingsTheme.greenBg)
        case .localNotInstalled:
            Button { openSection(lane.settingsSection) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(SettingsTheme.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lane.readinessReason.title)
                            .font(SettingsTheme.footnote.weight(.semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        Text(lane.readinessReason.detail)
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(SettingsTheme.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.amber)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).fill(SettingsTheme.amberBg))
                .overlay(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).strokeBorder(SettingsTheme.amber.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .cloudReady:
            HStack(spacing: 8) {
                pill(systemImage: "checkmark.circle.fill", text: "已就绪", color: SettingsTheme.green, bg: SettingsTheme.greenBg)
                Spacer(minLength: 0)
                Button("配置…") { openSection(lane.settingsSection) }
                    .buttonStyle(.plain)
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(SettingsTheme.wine)
            }
        case .cloudUnconfigured:
            Button { openSection(lane.settingsSection) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SettingsTheme.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lane.readinessReason.title)
                            .font(SettingsTheme.footnote.weight(.semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        Text(lane.readinessReason.detail)
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(SettingsTheme.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.amber)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).fill(SettingsTheme.amberBg))
                .overlay(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).strokeBorder(SettingsTheme.amber.opacity(0.4), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(systemImage: String, text: String, color: Color, bg: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: SkinMetrics.fsCaption, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(bg))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: SkinMetrics.fsCaption, weight: .semibold))
            .foregroundStyle(text == "本机" ? SettingsTheme.green : SettingsTheme.ink3)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(text == "本机" ? SettingsTheme.greenBg : SettingsTheme.sunk))
    }

    // MARK: - Options + selection

    private func options(for lane: ModelLaneInfo) -> [CurrentModelOption] {
        switch lane.lane {
        case .asr: return ModelRouteCatalog.asrOptions
        case .llm: return ModelRouteCatalog.llmOptions
        case .tts: return ModelRouteCatalog.ttsOptions
        case .ocr: return OCREngine.selectableCases.map {
            CurrentModelOption(id: $0.rawValue, title: $0.title, subtitle: "", badge: $0.isLocal ? "本机" : "云端")
        }
        }
    }

    @ViewBuilder
    private func pickerOptions(for lane: ModelLaneInfo) -> some View {
        let options = options(for: lane)
        if lane.lane == .asr {
            let cloud = options.filter { $0.badge == "云端" }
            let local = options.filter { $0.badge == "本机" }
            if !cloud.isEmpty {
                Section("云端") {
                    pickerOptionRows(cloud)
                }
            }
            if !local.isEmpty {
                Section("本机") {
                    pickerOptionRows(local)
                }
            }
        } else {
            pickerOptionRows(options)
        }
    }

    @ViewBuilder
    private func pickerOptionRows(_ options: [CurrentModelOption]) -> some View {
        ForEach(options) { option in
            Text(option.title).tag(option.id)
        }
    }

    private func optionBinding(for lane: ModelLaneInfo) -> Binding<String> {
        Binding(
            // Cheap UserDefaults-only read (no Keychain) so the dropdown reflects the choice
            // instantly, independent of the async readiness cache. Shared with `lanes()` via
            // the single `ModelLaneDisplay.currentOptionId` definition.
            get: { ModelLaneDisplay.currentOptionId(for: lane.lane) },
            set: { newID in select(lane: lane.lane, optionId: newID) })
    }

    private func select(lane: ModelLaneInfo.Lane, optionId: String) {
        switch lane {
        case .asr:
            ModelRouteSelectionActions.applyASRSelection(optionId)
            ASRResidencyPrewarm.onSelection(optionId)   // openless-style background prewarm
        case .llm:
            ModelRouteSelectionActions.applyLLMSelection(optionId)
        case .tts:
            ModelRouteSelectionActions.applyTTSSelection(optionId)
        case .ocr:
            ModelRouteSelectionActions.applyOCRSelection(optionId)
            PaddleOCRResidencyPrewarm.onSelection(optionId)
        }
    }
}
