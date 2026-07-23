import SwiftUI
import ResponsayCore

/// 560 — the transient「✓ 已按意图上屏 · ↩ 撤销」chip shown bottom-center for a few seconds after an
/// Intent-aware insert. Tapping「撤销」removes the exact verified text (or restores the selection it
/// replaced) — it NEVER writes the raw transcript back (that is the retired ↩原文 semantics). The
/// undo refuses silently if the field was edited past the insert; nothing in the document is guessed.
struct IntentUndoChipView: View {
    var vm: QuickCaptureViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("已按意图上屏")
                .font(.callout)
                .foregroundStyle(.primary)
            Divider().frame(height: 14)
            Button {
                Task { @MainActor in await vm.undoIntentInsertion() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("撤销")
                }
                .font(.callout.weight(.medium))
            }
            // Must be .plain in this non-key borderless panel (AppKit-backed styles crash it — same
            // constraint as RevertChipView / UnifiedCapsule).
            .buttonStyle(.plain)
            .help("删除刚写入的文本，或恢复被替换的选区；不会写回原始语音")
            .accessibilityLabel("撤销本次校验成稿的写入")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(20)
    }
}
