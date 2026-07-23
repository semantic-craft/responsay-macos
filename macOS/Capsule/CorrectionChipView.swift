import SwiftUI
import ResponsayCore

/// 518: the transient「纠正」chip shown bottom-center after a dictation that plausibly contains a
/// mis-heard proper noun (`looksLikeMishearCandidate`, or always when the user's「每次听写都显示」
/// setting is on). It names the suspected word —「DeepSeek」听对了吗？— so a first-time user knows
/// what it's for (user 2026-07-06: a bare「纠正…」left people unsure what to do; see
/// `MishearCandidates`). Tapping it opens the correction mini panel (pick the misheard word, type
/// the right spelling → dictionary + learned alias in one confirm).
///
/// Styled with the same warm-paper/wine `CapsuleSystemTheme` the main dictation pill uses
/// (user feedback 2026-07-03: the original plain-material chip read as visually inconsistent) —
/// no separate "已写入" confirmation text, just the action itself.
struct CorrectionChipView: View {
    var vm: QuickCaptureViewModel

    /// 「点名可疑词」文案（见 `MishearCandidates.chipTitle`），由 CapsulePanel 在显示瞬间定格。
    /// MUST stay a frozen `let`, never a live read of `vm.correctionOffer`: the chip's window size
    /// is measured once and frozen, so a body re-render that changes content size re-marks Update
    /// Constraints until AppKit's loop breaker throws — the 1.4.9 (117) crash was this title
    /// re-rendering live when the offer expired (10s) or was replaced by the next dictation.
    let title: String

    var body: some View {
        Button {
            vm.beginCorrection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CapsuleSystemTheme.accentText)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(CapsuleSystemTheme.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: CapsuleSystemTheme.pillHeight)
        }
        // ponytail: MUST be .plain, not an AppKit-backed style (.borderless/.bordered). A real
        // NSButton inside this non-key borderless panel posts _postWindowNeedsUpdateConstraints
        // during the CA layout commit → uncaught NSException → crash on every dictation (the
        // 1.3.22 regression). Same rule as RevertChipView / UnifiedCapsule.
        .buttonStyle(.plain)
        .help("英文词可能听错了？点一下改成正确写法，app 会记住，下次同样的错自动修正")
        .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(20)  // room for the shadow inside the panel bounds
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)，点一下可纠正并让 app 记住")
    }
}
