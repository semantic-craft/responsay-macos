import SwiftUI
import ResponsayCore

/// The `.copied` bottom-center pill — 方案 A「精简合并胶囊」(user 2026-07-05). Shown when a
/// dictation had no editable target: the text is auto-copied to the clipboard, and this card lets
/// the user re-copy or (when the text is mishear-shaped) open 纠正并学习. Replaces the old single-row
/// 「已复制：… · 📋」pill so 复制 and 纠正 stop fighting — 复制 is always the primary action, 纠正
/// appears only when `vm.correctionOffer != nil`.
///
/// Skin-driven `CapsuleSystemTheme` (paper + accent follow the active skin), matching
/// `CorrectionChipView`. Every
/// button is `.plain` — an AppKit-backed style crashes in this borderless non-key panel (1.3.22).
struct CopyCorrectPillView: View {
    var vm: QuickCaptureViewModel
    /// Write the shown text to the clipboard and dismiss the pill.
    var copyAction: () -> Void
    /// Open the「纠正并学习」mini panel on the shown text.
    var correctAction: () -> Void

    private var showsCorrection: Bool { vm.correctionOffer != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            summaryRow
            buttonRow
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 248)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(20)  // room for the shadow inside the panel bounds
        .accessibilityElement(children: .contain)
        .accessibilityLabel("听写已复制")
    }

    // MARK: - Summary (top): a short recap of what was said

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CapsuleSystemTheme.accentText)
                .accessibilityHidden(true)
            Text(vm.copiedText)
                .font(.system(size: 13.5))
                .tracking(0.6)                       // 放宽字距 — 比现版明显宽松
                .foregroundStyle(CapsuleSystemTheme.ink)
                .lineLimit(1)
                .truncationMode(.head)               // keep the newest words, like macOS dictation
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions (bottom): 复制 (primary) [ + 纠正 (secondary) ]

    private var buttonRow: some View {
        HStack(spacing: 8) {
            pillButton(title: "复制", systemName: "doc.on.doc", primary: true, action: copyAction)
                .accessibilityLabel("复制到剪贴板")
            if showsCorrection {
                pillButton(title: "纠正", systemName: "text.badge.checkmark", primary: false, action: correctAction)
                    .accessibilityLabel("纠正并学习")
            }
        }
    }

    private func pillButton(title: String, systemName: String, primary: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(primary ? CapsuleSystemTheme.accentInk : CapsuleSystemTheme.accentText)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(1.2)                   // 放大字距（本次诉求）
                    .foregroundStyle(primary ? CapsuleSystemTheme.accentInk : CapsuleSystemTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if primary {
                    Capsule(style: .continuous).fill(CapsuleSystemTheme.accent)
                } else {
                    Capsule(style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        // ponytail: MUST be .plain — a real NSButton in this borderless non-key panel crashes the
        // CA layout commit (the 1.3.22 regression). Same rule as CorrectionChipView / UnifiedCapsule.
        .buttonStyle(.plain)
    }
}
