import SwiftUI
import AppKit

struct SettingsStoragePane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @Binding var networkRegionRaw: String
    @Binding var localMirror: String
    @Binding var localEngineTTL: String
    let modelManagerSummary: String
    @Binding var modelManagers: [LocalModelDownloadManager]
    let residency: LocalEngineResidency
    @Binding var residencyError: String?
    @Binding var storageMigrationStatus: String?
    let ensureModelManagers: () -> Void
    let refreshModelManagerStatus: () async -> Void

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "离线模型下载与管理", desc: "下载内置离线模型、管理内存保留与存储位置。")

                WarmCard {
                    GroupLabel(text: "下载与内存")
                    pickerRow("网络环境") {
                        Picker("", selection: Binding(
                            get: { NetworkRegion(rawValue: networkRegionRaw) ?? NetworkRegion.localeDefault() },
                            set: { region in
                                networkRegionRaw = region.rawValue
                                NetworkRegion.select(region)
                            })) {
                            ForEach(NetworkRegion.allCases) { region in
                                Text(region.title).tag(region)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 280)
                    }
                    pickerRow("下载镜像") {
                        Picker("", selection: $localMirror) {
                            Text("GitHub 官方（海外网络）").tag("hf")
                            Text("国内代理（gh-proxy / ghfast 加速）").tag("cnproxy")
                        }
                        .labelsHidden().frame(maxWidth: 280)
                    }
                    pickerRow("引擎内存保留") {
                        Picker("", selection: $localEngineTTL) {
                            Text("即时释放").tag("0")
                            Text("5 分钟（默认）").tag("5")
                            Text("30 分钟").tag("30")
                            Text("常驻内存").tag("never")
                        }
                        .labelsHidden().frame(maxWidth: 280)
                    }
                    footnote("「网络环境」是引导里那次国内/海外选择（改它会同步下方镜像）；「下载镜像」可在其上手动覆盖。内置模型从 GitHub Releases 下载；国内网络选「国内代理」会优先走 gh-proxy / ghfast 镜像、不卡超时；下载中断会自动断点续传。内存保留＝最后一次使用后模型在内存里停留多久再释放。")
                }

                WarmCard {
                    GroupLabel(text: "轻量内置模型（开箱即用）")
                    if modelManagers.isEmpty {
                        Text("正在加载本地引擎清单…")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    } else {
                        ForEach(modelManagers) { manager in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(manager.displayName).foregroundStyle(appearanceStore.palette.ink)
                                    Text("\(Self.capabilityCaption(manager.spec.capability)) · \(manager.sizeText) · 原生支持，零配置")
                                        .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 6) {
                                    SettingsModelControls(manager: manager)
                                    SettingsResidencyControls(
                                        manager: manager,
                                        residency: residency,
                                        residencyError: $residencyError)
                                }
                            }
                        }
                        if let residencyError {
                            Text(residencyError).font(SettingsTheme.footnote).foregroundStyle(.orange)
                        }
                    }
                    footnote("包含 SenseVoice / Qwen3-ASR / Fun-ASR Nano（听写）、Kokoro（朗读）与中英标点模型（如实听写离线加标点）。App 内置原生支持，一键下载即可离线使用。")
                }

                WarmCard {
                    GroupLabel(text: "模型状态")
                    HStack(spacing: 8) {
                        Text(modelManagerSummary).foregroundStyle(appearanceStore.palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("刷新") { Task { await refreshModelManagerStatus() } }.controlSize(.small)
                    }
                }

                WarmCard {
                    GroupLabel(text: "存储")
                    HStack(spacing: 16) {
                        Text("存储位置").foregroundStyle(appearanceStore.palette.ink)
                        Spacer(minLength: 8)
                        Text(storageLocationLabel).foregroundStyle(appearanceStore.palette.ink2)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    HStack(spacing: 10) {
                        Button("在 Finder 中显示") { revealModelsFolder() }.controlSize(.small)
                        Button("更改存储位置…") { migrateStorage() }.controlSize(.small)
                        Spacer(minLength: 0)
                    }
                    if let status = storageMigrationStatus {
                        Text(status).font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    }
                    footnote("迁移会先校验复制并在新位置通过加载测试后才切换；删除旧文件需再次确认。")
                }
        }
        .navigationTitle("离线模型下载与管理")
        .onAppear {
            ensureModelManagers()
            Task { await refreshModelManagerStatus() }
        }
    }

    private func pickerRow<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(appearanceStore.palette.ink)
            Spacer(minLength: 8)
            content()
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func capabilityCaption(_ capability: LocalModelCapability) -> String {
        switch capability {
        case .tts: "文本朗读连接配置"
        case .ocr: "图片识别连接配置"
        case .punctuation: "如实听写离线加标点"
        case .asr, .llm: "语音识别连接配置"
        }
    }

    private var storageLocationLabel: String {
        (SenseVoiceModel.modelsRoot.path as NSString).abbreviatingWithTildeInPath
    }

    private func migrateStorage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选为模型目录"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let newRoot = chosen.appendingPathComponent("Responsay/models", isDirectory: true)
        storageMigrationStatus = "迁移中…"
        Task {
            do {
                let oldRoot = try await Task.detached {
                    try await LocalModelStorageMigration.migrate(
                        specs: LocalModelRegistry.all, to: newRoot)
                }.value
                storageMigrationStatus = "已迁移到 \(newRoot.path)"
                modelManagers.forEach { $0.refresh() }
                confirmDeleteOld(at: oldRoot)
            } catch {
                storageMigrationStatus = "迁移失败：\(error)"
            }
        }
    }

    private func confirmDeleteOld(at oldRoot: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "删除旧位置的模型文件？")
        alert.informativeText = String(localized: "新位置已通过加载测试。是否删除旧副本以释放空间？")
        alert.addButton(withTitle: String(localized: "删除旧文件"))
        alert.addButton(withTitle: String(localized: "保留"))
        if alert.runModal() == .alertFirstButtonReturn {
            try? LocalModelStorageMigration.deleteOld(at: oldRoot, specs: LocalModelRegistry.all)
            storageMigrationStatus = "已迁移并删除旧文件。"
        }
    }

    private func revealModelsFolder() {
        guard let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Responsay/models") else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
