import SwiftUI

/// Warm-paper tokens for the **Capsule System** (Claude Design handoff `Capsule System.dc.html`).
///
/// Deliberately **skin-independent**: the capsule is always warm paper + wine, regardless of the
/// app's active skin (荔园红 / 胡佛红 / 珞珈青 / 嘉庚蓝), so a green or blue skin never tints the
/// floating pill. Values mirror the design's `themeVars` 1:1. `DynamicColor.make` resolves
/// light/dark automatically. 永不纯黑 / 蓝.
enum CapsuleSystemTheme {
    /// surface ~96% alpha, sits over an `.ultraThinMaterial` (≈ the design's 20px backdrop blur).
    static let surface = DynamicColor.make(0xFBF6EC, 0x262018, lightA: 0.96, darkA: 0.96)
    static let ink = DynamicColor.make(0x2B2119, 0xF1E8DB)
    static let ink2 = DynamicColor.make(0x2B2119, 0xF1E8DB, lightA: 0.55, darkA: 0.55)
    static let line = DynamicColor.make(0x2B2119, 0xFFFFFF, lightA: 0.13, darkA: 0.12)
    static let chip = DynamicColor.make(0x2B2119, 0xFFFFFF, lightA: 0.08, darkA: 0.09)

    static let accent = DynamicColor.make(0x7B2D3A, 0x7B2D3A)
    /// Waveform / pulse dot — brightens in dark so it reads on the charcoal paper.
    static let accentText = DynamicColor.make(0x7B2D3A, 0xCB6072)
    static let accentInk = DynamicColor.make(0xFBF4EA, 0xFBF4EA)   // glyph on the accent
    static let accentSoft = DynamicColor.make(0x7B2D3A, 0xCB6072, lightA: 0.13, darkA: 0.16)
    static let glow = DynamicColor.make(0x7B2D3A, 0x7B2D3A, lightA: 0.4, darkA: 0.55)
    /// Left→right progress fill behind the thinking label.
    static let fill = DynamicColor.make(0x7B2D3A, 0x7B2D3A, lightA: 0.2, darkA: 0.85)

    static let err = DynamicColor.make(0xB23A2E, 0xE0796B)
    static let errSoft = DynamicColor.make(0xB23A2E, 0xE0796B, lightA: 0.12, darkA: 0.16)

    /// Soft drop shadow (never a hard black box).
    static let shadow = DynamicColor.make(0x46301E, 0x000000, lightA: 0.38, darkA: 0.6)
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
