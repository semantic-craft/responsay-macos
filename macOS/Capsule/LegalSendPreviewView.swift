import SwiftUI
import AppKit
import ResponsayCore

/// 110 — the send-preview shown before a cloud legal call that needs confirmation.
/// Lists EXACTLY which fields will be sent (never the whole document) + why a confirm
/// is required, then 确认发送 / 取消. A blocked decision never reaches here (it surfaces
/// as an error); this is only the `cloudRequiresUserConfirm` gate.
///
/// good-ui pass: spacing/radii from `MacMetrics`; Dynamic-Type semantic fonts.
struct LegalSendPreviewView: View {
    let decision: LegalPrivacyDecision
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetrics.m) {
            HStack(spacing: MacMetrics.s) {
                Image(systemName: "lock.shield").font(.callout).foregroundStyle(MacPalette.accent)
                Text("发送前确认").font(.caption.weight(.semibold)).textCase(.uppercase)
                    .kerning(0.4).foregroundStyle(MacPalette.accent)
            }

            Text("仅以下字段会发送到云端（绝不发送整篇文档）：")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                ForEach(decision.sendFields, id: \.self) { field in
                    Label { Text(field.label).font(.callout) } icon: {
                        Image(systemName: "arrow.up.forward.circle").font(.caption).foregroundStyle(MacPalette.accent)
                    }
                }
            }
            .padding(MacMetrics.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacPalette.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))

            if !decision.reasons.isEmpty {
                VStack(alignment: .leading, spacing: MacMetrics.xs) {
                    ForEach(decision.reasons, id: \.self) { reason in
                        Text("· \(reason)").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: MacMetrics.s) {
                Button { onConfirm() } label: { Label("确认发送", systemImage: "paperplane") }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent).tint(MacPalette.accent).foregroundStyle(MacPalette.accentInk)
                Button("取消") { onCancel() }.keyboardShortcut(.escape, modifiers: [])
                Spacer(minLength: 0)
            }
            .padding(.top, MacMetrics.hairline)
        }
        .padding(MacMetrics.l)
        .frame(width: 360, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous)
            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .padding(MacMetrics.xxl)
    }
}

#if DEBUG
#Preview("Send preview — confirm") {
    LegalSendPreviewView(decision: LegalPrivacyDecision(
        route: .cloudRequiresUserConfirm,
        sendFields: [.selectedText, .sceneTag, .appCategory],
        reasons: ["检测到敏感词「客户」，默认不自动发送云端。", "每次询问：发送云端前需确认。"]))
        .frame(width: 420, height: 380)
}
#endif
