import ResponsayCore
import SwiftUI

// MARK: - 5 · 开权限

struct PermissionsStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 36) {
                Text("感谢您的信任，\n我们重视您的隐私")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    // 屏幕录制不在这里要：它需要授权后重启才生效，放到第一次「截图翻译」或
                    // 图片识别设置里按需请求（见 CaptureSnapOCRController / SettingsOCRPane）。
                    ForEach(PermissionKind.allCases.filter { $0 != .screenRecording }) { permRow($0, p) }

                    Text("截图翻译的屏幕录制权限会在第一次使用时再请求。")
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(p.ink3)
                        .padding(.top, 4)
                }
            }
            .frame(width: 282, alignment: .leading)

            privacyPanel(p)
                .frame(width: 236)
                .frame(minHeight: 420)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 456, alignment: .center)
        .padding(.top, 8)
        // Poll live OS state while on this step: mic grants (in-app dialog) and accessibility
        // grants (System Settings) both land here, so the button flips to 已开启 without a re-tap.
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Trigger the real macOS authorization flow; live state is reflected by the `.task` poll.
    private func request(_ perm: PermissionKind) {
        switch perm {
        case .microphone:    _ = MicrophonePermission.promptIfNeeded()
        case .accessibility: AccessibilityPermission.requestFromUserAction()
        case .screenRecording:
            ScreenRecordingPermission.requestFromUserAction()
        }
        model.refreshPermissions()
    }

    @ViewBuilder private func permRow(_ perm: PermissionKind, _ p: SkinPalette) -> some View {
        let granted = model.granted.contains(perm)
        Button { request(perm) } label: {
            HStack(spacing: 14) {
                Text(permissionPrompt(for: perm))
                    .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle().fill(granted ? p.ink : p.accent)
                    Image(systemName: granted ? "checkmark" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(granted ? p.card : p.onAccent)
                }
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(granted ? p.hair : p.accentLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(granted)
    }

    private func permissionPrompt(for perm: PermissionKind) -> String {
        switch perm {
        case .microphone:
            "允许 \(AppBrand.displayName) 使用您的麦克风"
        case .accessibility:
            "允许 \(AppBrand.displayName) 将文本插入任意 App"
        case .screenRecording:
            "允许 \(AppBrand.displayName) 截图取字"
        }
    }

    private func privacyPanel(_ p: SkinPalette) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [p.accentWash, p.card2], startPoint: .topLeading, endPoint: .bottomTrailing))

            RoundedRectangle(cornerRadius: 120)
                .strokeBorder(p.card.opacity(0.38), lineWidth: 22)
                .frame(width: 210, height: 210)
                .offset(x: 52, y: -62)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 20) {
                    privacyRow(icon: "lock", title: "不经法言云端中转", detail: "语音和文本只走本机，或你在设置里选择的 BYOK 服务商。", p: p)
                    privacyRow(icon: "nosign", title: "不训练您的数据", detail: "法言不会把输入内容存入自家训练集，也不会上传到我们的服务器。", p: p)
                    privacyRow(icon: "laptopcomputer", title: "历史记录留在设备内", detail: "设置、词典与使用记录优先保留在这台 Mac。", p: p)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 26)
                .background(RoundedRectangle(cornerRadius: 14).fill(p.card.opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.hair, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 42)
            }
        }
        .clipped()
    }

    private func privacyRow(icon: String, title: String, detail: String, p: SkinPalette) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(p.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: SkinMetrics.fsCard, weight: .semibold))
                    .foregroundStyle(p.accent)
                Text(detail)
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
