import SwiftUI

/// Skin-driven tokens for the **Capsule System** (Claude Design handoff `Capsule System.dc.html`).
///
/// The capsule follows the app's active `Skin` (default 荔园红): paper / ink / hairline come from
/// the skin's card + ink family, the accent family (waveform, ✓, fill, glow) from the skin accent,
/// so 珞珈青 shows a green pill and 嘉庚蓝 a blue one. The design's `themeVars` *recipe* — which
/// token carries which alpha, wash-in-light vs near-solid-in-dark — is kept 1:1; only the source
/// hues moved from the fixed warm-paper/wine constants to `Skin.current`. Error red stays
/// semantic (not skinned). Tokens resolve the skin at render time, so a skin swap re-tints the
/// next capsule. 永不纯黑 / 蓝.
enum CapsuleSystemTheme {
    private static var p: SkinPalette { Skin.current.palette }
    private static var hx: (accentLight: UInt32, accentDark: UInt32, inkLight: UInt32) {
        Skin.current.capsuleHex
    }

    /// surface ~96% alpha, sits over an `.ultraThinMaterial` (≈ the design's 20px backdrop blur).
    static var surface: Color { p.card.opacity(0.96) }
    static var ink: Color { p.ink }
    static var ink2: Color { p.ink.opacity(0.55) }
    static var line: Color { p.ink.opacity(0.125) }
    static var chip: Color { p.ink.opacity(0.085) }

    static var accent: Color { p.accent }
    /// Waveform / pulse dot — the skin's dark accent is already brightened so it reads on dark paper.
    static var accentText: Color { p.accent }
    static var accentInk: Color { p.onAccent }   // glyph on the accent
    static var accentSoft: Color {
        DynamicColor.make(hx.accentLight, hx.accentDark, lightA: 0.13, darkA: 0.16)
    }
    static var glow: Color {
        DynamicColor.make(hx.accentLight, hx.accentLight, lightA: 0.4, darkA: 0.55)
    }
    /// Left→right progress fill behind the thinking label (brand hue in both modes, like the
    /// original wine: a light wash in light, near-solid in dark).
    static var fill: Color {
        DynamicColor.make(hx.accentLight, hx.accentLight, lightA: 0.2, darkA: 0.85)
    }

    static let err = DynamicColor.make(0xB23A2E, 0xE0796B)
    static let errSoft = DynamicColor.make(0xB23A2E, 0xE0796B, lightA: 0.12, darkA: 0.16)

    /// Soft drop shadow (never a hard black box) — tinted by the skin's ink in light.
    static var shadow: Color {
        DynamicColor.make(hx.inkLight, 0x000000, lightA: 0.38, darkA: 0.6)
    }
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 8

    // Anatomy — the pill never jumps between listening and thinking (both 160 × 36).
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
