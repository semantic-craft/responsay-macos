import SwiftUI
import ResponsayCore

/// Revert AI (P0b): the transient「✓ 已写入 · ↩ 原文」chip shown bottom-center for a few seconds
/// after a dictation insert whose AI output differs from the raw transcript. Tapping「原文」swaps
/// the inserted text back to what the user actually said. Non-activating panel hosts this; the
/// button works without bringing Responsay to the front.
struct RevertChipView: View {
    var vm: QuickCaptureViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("已写入")
                .font(.callout)
                .foregroundStyle(.primary)
            Divider().frame(height: 14)
            Button {
                Task { @MainActor in await vm.revertLastInsertion() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("原文")
                }
                .font(.callout.weight(.medium))
            }
            // ponytail: MUST be .plain, not an AppKit-backed style (.borderless/.bordered). A real
            // NSButton inside this non-key borderless panel posts _postWindowNeedsUpdateConstraints
            // during the CA layout commit → uncaught NSException → crash on every dictation (1.3.22
            // regression). UnifiedCapsule's buttons use .plain in this same panel type for this reason.
            .buttonStyle(.plain)
            .help("把刚写入的 AI 文本换回你说的原文")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(20)  // room for the shadow inside the panel bounds
    }
}
