import SwiftUI

/// The settings swatch for 外观主题 → 录音胶囊外观, laid out beside its siblings in a 3-wide grid.
///
/// Like `SkinSwatchCard`, the preview renders in the **card's own** colour world while the chrome
/// (border, text, badge) uses the **active** `Skin`, so the current choice reads clearly against
/// the rest of settings.
///
/// The preview is a hand-drawn miniature rather than a live `UnifiedCapsule`: that view resolves
/// `CapsuleSkin.current` at render time (by design — it is what makes a skin swap re-dress the
/// next capsule), so it cannot be asked to draw a skin the user has not chosen yet. The miniature
/// shows the three things that actually distinguish the skins: surface, accent, and whether the
/// live slot holds a waveform or a mono-eye.
struct CapsuleSkinCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let capsuleSkin: CapsuleSkin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let active = appearance.palette
        let ct = capsuleSkin.tokens(mode: .voice)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview(ct, active: active)
                footer(active)
            }
            .background(active.card2)
            .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                    .strokeBorder(isSelected ? active.accent : active.hair,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.05),
                    radius: isSelected ? 7 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(capsuleSkin.displayName)，\(capsuleSkin.tagline)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Capsule miniature (capsule skin's own tokens)

    /// A desk-like ground so the translucent skins have something to sit on — 光之骨架 is mostly
    /// glow, and on a flat card colour it would read as a grey lozenge.
    private func preview(_ ct: CapsuleTokens, active: SkinPalette) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [active.sidebar, active.bg],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            miniPill(ct)
            if isSelected { checkBadge(active).padding(10) }
        }
        .frame(height: 118)
    }

    private func miniPill(_ ct: CapsuleTokens) -> some View {
        HStack(spacing: 7) {
            Circle().fill(ct.chip)
                .overlay(Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(ct.ink2))
                .frame(width: 22, height: 22)

            liveSlot(ct).frame(width: 50)

            Circle().fill(ct.accent)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ct.accentInk))
                .frame(width: 22, height: 22)
                .shadow(color: ct.glow, radius: 5, y: 2)
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(ct.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .background(CapsuleSkinChrome(skin: capsuleSkin).clipShape(Capsule(style: .continuous)))
        .overlay(Capsule(style: .continuous).strokeBorder(ct.line, lineWidth: 1.2))
        .shadow(color: ct.shadow, radius: 10, y: 5)
    }

    /// 夏亚红 puts a lens where every other skin puts bars — the one structural difference worth
    /// showing at swatch size.
    @ViewBuilder private func liveSlot(_ ct: CapsuleTokens) -> some View {
        if capsuleSkin == .zaku {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.03, blue: 0.04))
                Circle()
                    .fill(RadialGradient(stops: [.init(color: .white, location: 0),
                                                 .init(color: ct.accent, location: 0.32),
                                                 .init(color: ct.accent.opacity(0), location: 0.74)],
                                         center: UnitPoint(x: 0.5, y: 0.45),
                                         startRadius: 0, endRadius: 8))
                    .frame(width: 12, height: 12)
                    .shadow(color: ct.glow, radius: 4)
                    .offset(x: 6)
            }
            .frame(height: 13)
        } else {
            HStack(spacing: 2) {
                ForEach(Array([5.0, 9.0, 13.0, 7.0, 11.0, 6.0, 9.0].enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ct.accentText)
                        .frame(width: 2, height: h)
                }
            }
            .frame(height: 13)
        }
    }

    private func checkBadge(_ active: SkinPalette) -> some View {
        ZStack {
            Circle().fill(active.accent)
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(active.onAccent)
        }
        .frame(width: 20, height: 20)
        .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
    }

    // MARK: - Footer

    private func footer(_ active: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(capsuleSkin.displayName)
                .font(.system(size: SkinMetrics.fsCard, weight: .semibold))
                .foregroundStyle(active.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(capsuleSkin.tagline)
                .font(.system(size: SkinMetrics.fsLabel))
                .foregroundStyle(active.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? active.accentWash : Color.clear)
        .overlay(Rectangle().fill(active.hair).frame(height: 1), alignment: .top)
    }
}
