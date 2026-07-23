import SwiftUI

/// The settings-only skin swatch used in 外观主题 → 配色方案 (laid out in a 3-wide grid).
///
/// Distinct from onboarding's `OBSkinCard`: sized for a multi-column grid so the display name
/// never wraps character-by-character, with a larger colour-world preview and a cleaner selected
/// state (accent ring + check badge instead of a radio dot). The preview renders in the card's
/// **own** palette so each swatch previews its colour world; the chrome (border, text, badge)
/// uses the **active** palette so the current choice reads clearly.
struct SkinSwatchCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let skin: Skin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let active = appearance.palette
        let sp = skin.palette
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview(sp, active: active)
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
        .accessibilityLabel(Text("\(skin.displayName)，\(skin.tagline)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Colour-world preview (skin's own palette)

    private func preview(_ sp: SkinPalette, active: SkinPalette) -> some View {
        ZStack(alignment: .topTrailing) {
            sp.bg
            paper(sp).padding(14)
            if isSelected { checkBadge(active).padding(10) }
        }
        .frame(height: 118)
    }

    /// A floating "page" showing an accent underline + Aa (top-left) and two swatch dots (bottom-right).
    private func paper(_ sp: SkinPalette) -> some View {
        RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .fill(sp.card)
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(sp.hair, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(sp.accent).frame(width: 34, height: 6)
                    Text("Aa").font(SkinMetrics.serif(28, weight: .regular)).foregroundStyle(sp.ink)
                }
                .padding(16)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 5) {
                    Circle().fill(sp.accent).frame(width: 9, height: 9)
                    Circle().fill(sp.accentDeep).frame(width: 9, height: 9)
                }
                .padding(16)
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

    // MARK: - Footer (name + tagline + selected wash)

    private func footer(_ active: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skin.displayName)
                .font(.system(size: SkinMetrics.fsCard, weight: .semibold))
                .foregroundStyle(active.ink)
                .lineLimit(1)
            Text(skin.tagline)
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
