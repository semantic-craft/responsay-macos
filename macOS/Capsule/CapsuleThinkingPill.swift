import SwiftUI

// MARK: - Thinking pill (same width as listening; fill / eye / arc per choreography)

struct CapsuleThinkingPill: View {
    let label: String
    let tokens: CapsuleTokens
    let skin: CapsuleSkin
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0.06

    private var chore: CapsulePhaseChoreography { skin.choreography }

    var body: some View {
        HStack(spacing: CapsuleSystemTheme.slotGap) {
            if chore == .signature {
                MonoEyeBadge(phase: .thinking, tint: tokens.accent,
                             glow: tokens.glow, alarmTint: tokens.err)
                    .frame(width: CapsuleSystemTheme.slotSide)
            }
            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .tracking(0.7)               // ≈ letter-spacing .05em
                .foregroundStyle(tokens.ink)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CapsuleSystemTheme.outerPad)
        .frame(width: CapsuleSystemTheme.liveWidth, height: CapsuleSystemTheme.pillHeight)
        .background(alignment: .leading) {
            // Only `.fillSweep` spends the pill's interior on progress. `.signature` reads it off
            // the breathing lens; `.edgeArc` keeps the interior clear on purpose.
            if chore == .fillSweep {
                Rectangle()
                    .fill(tokens.fill)
                    .frame(width: CapsuleSystemTheme.liveWidth * progress,
                           height: CapsuleSystemTheme.pillHeight)
            }
        }
        .background(Capsule(style: .continuous).fill(tokens.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .background(CapsuleSkinChrome(skin: skin).clipShape(Capsule(style: .continuous)))
        .overlay(Capsule(style: .continuous).strokeBorder(tokens.line, lineWidth: 1.5))
        .overlay {
            if chore == .edgeArc {
                CapsuleEdgeArc(kind: .running, width: CapsuleSystemTheme.liveWidth,
                               color: tokens.accent, glow: tokens.glow)
            }
        }
        .shadow(color: tokens.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .onAppear {
            guard chore == .fillSweep else { return }
            if reduceMotion {
                progress = 0.7   // jump to a stable fill instead of sweeping
            } else {
                withAnimation(.timingCurve(0.3, 0.55, 0.35, 1, duration: 1.6)) { progress = 1.0 }
            }
        }
        .accessibilityLabel(label)
    }
}

