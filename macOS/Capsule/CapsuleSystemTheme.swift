import SwiftUI

/// Tokens for the **Capsule System** (Claude Design handoff `Capsule System.dc.html`), resolved
/// from the active `CapsuleSkin`.
///
/// Two axes meet here. `CapsuleSkin` picks the capsule's colour world; its default `.followSkin`
/// derives every token from the app-wide `Skin` exactly as this enum used to, so 珞珈青 still shows
/// a green pill and nothing about the default install changed. The 高达 skins opt out of `Skin`
/// and carry fixed palettes — see `CapsuleTokens`.
///
/// The static accessors below are the **听写-side** surface: `CopyCorrectPillView`,
/// `IntentReviewCardView`, `CorrectionLearnView` and friends all render on the dictation path, so
/// resolving at `.voice` is correct for them by construction. `UnifiedCapsule` is the one view
/// rendered in *both* modes, and it calls `tokens(mode:)` directly — that is what lets 光之骨架
/// turn pink for 提问 without threading a mode parameter through 132 call sites.
///
/// Anatomy constants are skin-independent: the pill never jumps between listening and thinking,
/// whichever skin is on. 永不纯黑 / 蓝.
enum CapsuleSystemTheme {
    /// Token set for a given mode. The only caller that needs a non-default mode is
    /// `UnifiedCapsule`; everything else is dictation-side.
    static func tokens(mode: CapsuleMode = .voice) -> CapsuleTokens {
        CapsuleSkin.current.tokens(mode: mode)
    }

    static var choreography: CapsulePhaseChoreography { CapsuleSkin.current.choreography }

    // MARK: - 听写-side accessors (resolve at .voice)

    static var surface: Color { tokens().surface }
    static var ink: Color { tokens().ink }
    static var ink2: Color { tokens().ink2 }
    static var line: Color { tokens().line }
    static var chip: Color { tokens().chip }

    static var accent: Color { tokens().accent }
    static var accentText: Color { tokens().accentText }
    static var accentInk: Color { tokens().accentInk }
    static var accentSoft: Color { tokens().accentSoft }
    static var glow: Color { tokens().glow }
    static var fill: Color { tokens().fill }

    static var err: Color { tokens().err }
    static var errSoft: Color { tokens().errSoft }

    /// Soft drop shadow (never a hard black box).
    static var shadow: Color { tokens().shadow }
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 8

    // MARK: - Anatomy (skin-independent)
    //
    // The pill never jumps between listening and thinking (both 160 × 36).
    // Height matched to Typeless (~36); width kept a touch larger.
    static let pillHeight: CGFloat = 36
    static let cornerRadius: CGFloat = 18      // height ÷ 2
    static let liveWidth: CGFloat = 160        // listening == thinking, fixed
    static let slotSide: CGFloat = 30          // ✕ / ✓ control slot
    static let slotWave: CGFloat = 72          // waveform slot
    static let outerPad: CGFloat = 6
    static let slotGap: CGFloat = 8
    static let stackGap: CGFloat = 7           // ask-label ↔ pill
}
