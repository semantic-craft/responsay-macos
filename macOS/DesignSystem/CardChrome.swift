import SwiftUI

// MARK: - 311 · Card family chrome + shadow scale

/// The 3-level shadow scale (issue 311): the audit found 15 hand-rolled shadow
/// recipes, 6 of them near-duplicate "floating layer" values. New code picks a
/// level instead of inventing opacity/radius/y triples.
enum CardShadow {
    /// No elevation (flat panel inside another card).
    case none
    /// Resting card on the page — a soft real lift (was a near-invisible
    /// 0.05/1/1) so ivory cards read clearly against the parchment field.
    case rest
    /// Floating layer: popovers, previews, hotkey badges.
    case floating
    /// Hero/modal emphasis.
    case hero

    var opacity: Double {
        switch self {
        case .none: 0
        case .rest: 0.10
        case .floating: 0.12
        case .hero: 0.2
        }
    }
    var radius: CGFloat {
        switch self {
        case .none: 0
        case .rest: 6
        case .floating: 10
        case .hero: 24
        }
    }
    var y: CGFloat {
        switch self {
        case .none: 0
        case .rest: 2
        case .floating: 4
        case .hero: 10
        }
    }
}

/// The shared warm-paper card chrome: one fill + hairline + radius recipe.
/// Replaces the per-screen `private var card` replicas (Overview / History /
/// Polish / CoachPopup all hand-rolled the same RoundedRectangle pair).
/// Reads `SettingsTheme` statics (→ `Skin.current.palette`), matching what
/// both `WarmCard` and every replica already did.
struct WarmCardSurface: ViewModifier {
    var radius: CGFloat = SkinMetrics.radiusCard
    var shadow: CardShadow = .none

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(SettingsTheme.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(SettingsTheme.hair, lineWidth: 1))
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

extension View {
    /// Apply the family card chrome. Use this instead of re-rolling
    /// `RoundedRectangle(...).fill(card)` + `strokeBorder(hair)` backgrounds.
    func warmCardSurface(
        radius: CGFloat = SkinMetrics.radiusCard,
        shadow: CardShadow = .none
    ) -> some View {
        modifier(WarmCardSurface(radius: radius, shadow: shadow))
    }

    /// Apply a scale shadow without the card chrome (for floating layers that
    /// have their own material background).
    func cardShadow(_ level: CardShadow) -> some View {
        shadow(color: .black.opacity(level.opacity), radius: level.radius, y: level.y)
    }
}
