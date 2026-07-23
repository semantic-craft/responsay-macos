import SwiftUI
import ResponsayCore

/// 图片识别 (OCR) settings pane — the peer of `SettingsASRPane` / `SettingsTTSPane` in the「模型」group.
/// Per the hybrid decision (parallel placement, anamra-style internals): the engine is picked here and
/// surfaced in the main-window「模型选择」as「图片识别模型」, but the cloud engines (Mistral / 百度) are
/// configured with plain per-engine key fields instead of the OpenAI-`/models`-shaped `CapabilityCardView`
/// (those OCR APIs are a fixed-model `/v1/ocr` and a two-key OAuth flow — they don't fit that card).
struct SettingsOCRPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    @Binding var ocrEngineRaw: String
    let modelManagers: [LocalModelDownloadManager]
    let residency: LocalEngineResidency
    @Binding var residencyError: String?
    let ensureModelManagers: () -> Void
    let refreshModelManagerStatus: () async -> Void

    @State private var screenRecordingAuthorized = ScreenRecordingPermission.isAuthorized
    @State private var mistralKey = BYOKKeychain.read(OCRCredentialAccount.mistralAPIKey) ?? ""
    @State private var baiduKey = BYOKKeychain.read(OCRCredentialAccount.baiduAPIKey) ?? ""
    @State private var baiduSecret = BYOKKeychain.read(OCRCredentialAccount.baiduSecretKey) ?? ""

    @AppStorage(SnapTranslateTargetSettings.key)
    private var snapTargetRaw = SnapTranslateTargetSettings.defaultTarget.rawValue
    @AppStorage(SnapOCRCopySettings.key) private var snapCopyToClipboard = false
    @AppStorage(SnapCopySoundSettings.key) private var snapCopySound = true

    private var engine: OCREngine { OCREngine(rawValue: ocrEngineRaw) ?? .appleVision }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "图片识别连接配置", desc: "选择「截图翻译」用哪个 OCR 引擎识别屏幕上的文字。")

            SettingsStatusBar {
                StatusDot(state: isReady ? .green : .amber)
                Text("当前取字引擎：\(engine.title)")
                Spacer(minLength: 0)
                Text("截图翻译 OCR 用这一路")
                    .foregroundStyle(appearanceStore.palette.ink3)
            }

            screenRecordingCard

            WarmCard {
                CapabilityHeader(
                    systemImage: "text.viewfinder",
                    title: "图片识别 (OCR)",
                    subtitle: "用「截图翻译」快捷键框选屏幕 → 识别成文字 → 忠实准确地翻译成目标语言。这里选用哪个引擎：Apple Vision 在本机识别、不上传截图；云端引擎用你的密钥直连（存本机钥匙串）。")
                WarmDivider()

                LabeledRow(label: "取字引擎") {
                    Picker("", selection: $ocrEngineRaw) {
                        ForEach(OCREngine.selectableCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 260)
                    .onChange(of: ocrEngineRaw) { _, newValue in
                        PaddleOCRResidencyPrewarm.onSelection(newValue)
                    }
                }

                if engine == .mistral { mistralFields }
                if engine == .baidu { baiduFields }
                if engine == .paddleOCRLocal { paddleLocalNote }
                if !engine.isLocal { cloudPrivacyNote }
                if !isReady { fallbackHint }
            }

            snapBehaviorCard

            SettingsLocalModelCard(
                capability: .ocr,
                title: "本地截图翻译 OCR 模型",
                subtitle: "PaddleOCR v6 Small 在本机识别截图区域，不上传图片。下载约 31MB；未安装时会回落到 Apple Vision。",
                modelManagers: modelManagers,
                residency: residency,
                residencyError: $residencyError)
        }
        .navigationTitle("图片识别连接配置")
        .onAppear {
            ensureModelManagers()
            screenRecordingAuthorized = ScreenRecordingPermission.isAuthorized
            PaddleOCRResidencyPrewarm.onSelection(ocrEngineRaw)
            Task { await refreshModelManagerStatus() }
        }
        // Screen Recording is granted in System Settings (out of process); poll so the card
        // flips to ✓ without the user re-opening the pane.
        .task {
            while !Task.isCancelled {
                let authorized = ScreenRecordingPermission.isAuthorized
                if authorized != screenRecordingAuthorized { screenRecordingAuthorized = authorized }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // MARK: - 屏幕录制权限（按需，截图翻译/截图取字 需要）

    /// Screen Recording is requested on demand (not in onboarding) because macOS only applies a
    /// fresh grant to a relaunched process. When missing, offer 打开设置 + 真·重启（AppRelaunch）.
    private var screenRecordingCard: some View {
        WarmCard {
            CapabilityHeader(
                systemImage: "rectangle.dashed.badge.record",
                title: "屏幕录制权限",
                subtitle: "截图翻译 / 截图取字需要屏幕录制权限来截取你框选的屏幕区域，仅在你主动截图时使用。")
            WarmDivider()

            if screenRecordingAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(SettingsTheme.green)
                    Text("已授权 —— 截图翻译可以直接使用。")
                        .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink2)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SettingsTheme.amber)
                        Text("尚未授权。请在 系统设置 › 隐私与安全性 › 屏幕录制 里勾选 Responsay；macOS 要求授权后重启应用才会生效。")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button("打开屏幕录制设置") { ScreenRecordingPermission.requestFromUserAction() }
                        Button("重启 Responsay") { AppRelaunch.relaunch() }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - 截图行为（截图翻译目标语言 + 截图取字 复制方式）

    private var snapBehaviorCard: some View {
        WarmCard {
            CapabilityHeader(
                systemImage: "character.book.closed",
                title: "截图翻译 / 截图取字 / 截图复制",
                subtitle: "截图翻译要译成哪种语言；截图取字后是直接复制还是弹出可编辑面板；截图复制把图片本身放进剪贴板。")
            WarmDivider()

            LabeledRow(label: "截图翻译目标语言") {
                Picker("", selection: $snapTargetRaw) {
                    ForEach(SnapTranslateTarget.allCases) { target in
                        Text(target.label).tag(target.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            // footnote 用 ink2(非 ink3):说明性正文须达 AA 对比度（家族设计审计 A）。
            Text("默认「自动」：外文截图译成你的母语，母语截图译成外语（母语 / 外语在「翻译语言」设置里）。也可在此固定成中文 / 英语 / 德语 / 日语。两者的快捷键可在「快捷键」设置里自定义。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)

            WarmDivider()

            SettingsToggleRow(
                title: "截图取字直接复制到剪贴板",
                desc: "开启后，截图取字后直接写入剪贴板，不弹出可编辑结果面板。",
                binding: $snapCopyToClipboard)

            WarmDivider()

            SettingsToggleRow(
                title: "截图复制提示音",
                desc: "框选屏幕区域后，直接把图片本身复制到剪贴板，可粘贴到备忘录、聊天、邮件、图片编辑器等。不取字、不翻译。触发快捷键在「快捷键」设置里自定义。开启后，复制完成时播放提示音。",
                binding: $snapCopySound)
        }
    }

    private var paddleLocalNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(SettingsTheme.green)
            Text("PaddleOCR 使用本地 ONNX 模型识别截图区域。当前版本优先覆盖网页、PDF 和普通水平排版截图；旋转、弯曲文字或复杂表格仍可切回 Apple Vision / 云端 OCR。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Per-engine credential fields

    @ViewBuilder private var mistralFields: some View {
        WarmDivider()
        LabeledRow(label: "Mistral API Key") {
            SecureKeyField(placeholder: "ms-… / sk-…", text: $mistralKey)
                .frame(maxWidth: 360)
                .onChange(of: mistralKey) { _, newValue in
                    BYOKKeychain.write(newValue, account: OCRCredentialAccount.mistralAPIKey)
                }
        }
        Text("专用文档 OCR（mistral-ocr-latest），擅长论文 / 复杂排版。端点 api.mistral.ai/v1/ocr。")
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
    }

    @ViewBuilder private var baiduFields: some View {
        WarmDivider()
        LabeledRow(label: "百度 API Key") {
            SecureKeyField(placeholder: "百度智能云 API Key", text: $baiduKey)
                .frame(maxWidth: 360)
                .onChange(of: baiduKey) { _, newValue in
                    BYOKKeychain.write(newValue, account: OCRCredentialAccount.baiduAPIKey)
                }
        }
        LabeledRow(label: "百度 Secret Key") {
            SecureKeyField(placeholder: "对应 API Key 的 Secret Key", text: $baiduSecret)
                .frame(maxWidth: 360)
                .onChange(of: baiduSecret) { _, newValue in
                    BYOKKeychain.write(newValue, account: OCRCredentialAccount.baiduSecretKey)
                }
        }
        Text("百度智能云 OCR，两步鉴权：用 API Key + Secret Key 换取访问令牌。便宜、中文强。")
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
    }

    /// Cloud engines upload the captured region to a third-party service. Surface that plainly — this
    /// app's users routinely snap sensitive / privileged material, and the on-device path does not.
    private var cloudPrivacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(SettingsTheme.amber)
            Text("隐私提醒：选择云端引擎后，每次截图翻译都会把所选区域的图像上传到该服务商。涉及敏感或保密材料时，请改用 Apple Vision（本机，截图不离开这台 Mac）。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fallbackHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SettingsTheme.amber)
            Text(fallbackText)
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink2)
        }
    }

    private var fallbackText: String {
        switch engine {
        case .paddleOCRLocal:
            return "尚未下载 PaddleOCR 本地模型，截图翻译会暂时回落到 Apple Vision。"
        default:
            return "尚未填写完整密钥，截图翻译会暂时回落到本机 Apple Vision。"
        }
    }

    /// Apple Vision is always ready; PaddleOCR is ready once its local files are installed; a cloud
    /// engine is ready once its key(s) are present.
    private var isReady: Bool {
        switch engine {
        case .appleVision:
            return true
        case .paddleOCRLocal:
            return LocalModelRegistry.defaultOCR.isInstalled
        case .mistral:
            return !mistralKey.trimmingCharacters(in: .whitespaces).isEmpty
        case .baidu:
            return !baiduKey.trimmingCharacters(in: .whitespaces).isEmpty
                && !baiduSecret.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
