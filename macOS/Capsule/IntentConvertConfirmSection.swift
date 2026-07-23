import SwiftUI
import ResponsayCore

/// The "转普通听写" control, shared by the needs-review and safe-unavailable cards. It is a
/// deliberately two-step, INDEPENDENT decision (#559 铁律: 转普通 Dictate 必须独立用户决定且 route
/// 可见) — never a one-click "insert raw / continue as-is". Collapsed it is a single button;
/// expanded it spells out that ordinary Dictate skips intent re-organization and the改口/旁注
/// safety checks, then asks for an explicit confirm.
struct IntentConvertConfirmSection: View {
    var vm: QuickCaptureViewModel
    @State private var confirming = false

    var body: some View {
        if confirming {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("转为普通听写？将用「意图成稿」把原话直接上屏，不做意图重组，也不再校验改口与旁注。")
                        .font(.caption)
                        .foregroundStyle(CapsuleSystemTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .foregroundStyle(CapsuleSystemTheme.accentText)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("返回") { confirming = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(CapsuleSystemTheme.ink2)
                        .accessibilityLabel("返回，不转普通听写")
                    Button {
                        Task { await vm.convertIntentToOrdinaryDictate() }
                    } label: {
                        Text("确定转换")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.accent))
                            .foregroundStyle(CapsuleSystemTheme.accentInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("确定转为普通听写，直接上屏")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(CapsuleSystemTheme.accentSoft))
        } else {
            Button { confirming = true } label: {
                Label("转普通听写…", systemImage: "arrow.uturn.forward")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CapsuleSystemTheme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("转为普通听写，需再次确认")
            .accessibilityHint("普通听写会用意图成稿直接上屏，不做意图重组")
        }
    }
}
