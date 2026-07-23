import SwiftUI

/// Privacy & permissions: the three macOS authorizations the app needs (辅助功能 /
/// 麦克风 / 屏幕录制), managed in one place, plus the cloud data-boundary notes.
/// Self-contained — owns its permission state and polls live OS state while visible,
/// so grants made in System Settings flip the chips without a re-tap.
struct SettingsPrivacyPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var micGranted = MicrophonePermission.isGranted
    @State private var screenGranted = ScreenRecordingPermission.isAuthorized

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "隐私与权限", desc: "系统权限与上云数据的边界控制。")

            WarmCard {
                CardHeader(systemImage: "lock.shield", title: "系统权限",
                           subtitle: "听写、插入、截图所需的三项 macOS 授权。", accent: SettingsTheme.cSys)
                WarmDivider()
                permissionRow(
                    title: "辅助功能",
                    subtitle: "读取选中文本、注入改写结果所必需。",
                    granted: accessibilityTrusted,
                    request: { AccessibilityPermission.requestFromUserAction(); refresh() },
                    openSettings: AccessibilityPermission.openSystemSettings)
                WarmDivider()
                permissionRow(
                    title: "麦克风",
                    subtitle: "语音输入（听写 / 提问 / 翻译）录音所必需。",
                    granted: micGranted,
                    request: { _ = MicrophonePermission.promptIfNeeded(); refresh() },
                    openSettings: MicrophonePermission.openSystemSettings)
                WarmDivider()
                permissionRow(
                    title: "屏幕录制",
                    subtitle: "截图识别（OCR）所必需；首次授权后通常需重启一次。",
                    granted: screenGranted,
                    request: {
                        ScreenRecordingPermission.requestFromUserAction()
                        refresh()
                    },
                    openSettings: ScreenRecordingPermission.openSystemSettings)
                VStack(alignment: .leading, spacing: 4) {
                    Text("启用辅助功能权限后，会读取目标 App、窗口标题、光标附近文本和选中文本，用于本机的上下文判断与热词偏置（不上传）。另：「技能偏好 → 屏幕上下文」开启时（默认开），地道外文与任意提问会把当前应用、窗口标题和屏幕可见文字随提问发给你配置的云端 AI；密码框等敏感场景始终跳过，可在该处随时关闭。")
                    Text("VS Code 需在其设置开启 Editor: Accessibility Support 才能读到光标上下文；少数 App 无法暴露，会标为「光标上下文不可用」，不影响输入。")
                }
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }

            WarmCard {
                GroupLabel(text: "你的数据去哪儿了")
                Text("法言没有自己的服务器。你的语音、识别出的文字、改写结果，要么只留在这台电脑上（用本地模型时），要么直接发给你自己配置的云端模型供应商（用你填的 API Key），中间不经过我们的任何服务器。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("所以走云端时，你的内容会交给你选的那家供应商处理；它怎么保存、怎么使用这些数据，要看这家供应商自己的隐私政策。在意隐私的内容，建议优先用本地模型——不上传、也不离开这台电脑。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("隐私与权限")
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
        micGranted = MicrophonePermission.isGranted
        screenGranted = ScreenRecordingPermission.isAuthorized
    }

    @ViewBuilder private func permissionRow(
        title: String, subtitle: String, granted: Bool,
        request: @escaping () -> Void, openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(appearanceStore.palette.ink)
                Text(subtitle).font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
            }
            Spacer(minLength: 8)
            MemChip(resident: granted, residentLabel: "已授权", outLabel: "未授权")
            Button(granted ? "管理" : "请求权限") {
                if granted { openSettings() } else { request() }
            }
        }
    }
}
