import SwiftUI
import AppKit

/// Warm-paper + wine design tokens for the macOS settings surface.
///
/// Ported 1:1 from the Claude Design handoff `rs/styles.css` (Scheme B「册页」).
/// Replaces the native inset-grey `Form` look with a parchment window, ivory
/// cards, and a single 石榴红/wine accent, on a larger + denser type scale.
/// Light/dark adaptive via `NSColor` dynamic providers — no asset catalog.
///
/// taste-skill dials: VISUAL_DENSITY ↑, MOTION none, VARIANCE low.
enum SettingsTheme {

    // MARK: - Brand (the single accent — skin-driven via `Skin.current`, default 荔园红)
    //
    // The `wine*` names are kept for call-site stability; they now resolve from the active skin's
    // accent so the whole settings surface follows the chosen skin (荔园红 / 胡佛红). For the
    // default 荔园红 skin these are identical to the former literals.

    static var wine: Color { Skin.current.palette.accent }
    static var wineDeep: Color { Skin.current.palette.accentDeep }
    static var wineTint: Color { Skin.current.palette.accentWash }
    static var wineTint2: Color { Skin.current.palette.accentWash2 }
    static var wineLine: Color { Skin.current.palette.accentLine }

    // MARK: - Surfaces (skin-driven where the skin defines an exact match)

    static var bg: Color { Skin.current.palette.bg }            // parchment / cold-grey window field
    static var sidebar: Color { Skin.current.palette.sidebar }
    static var card: Color { Skin.current.palette.card }        // ivory / paper card
    static var card2: Color { Skin.current.palette.card2 }
    static let sunk = dyn(0xE8E2D8, 0x16140F)
    static var field: Color { Skin.current.palette.field }
    static let fieldBorder = dyn(0x4B3F31, 0xECE4D8, lightA: 0.18, darkA: 0.18)

    // MARK: - Ink + hairlines

    static var ink: Color { Skin.current.palette.ink }
    static var ink2: Color { Skin.current.palette.ink2 }
    static var ink3: Color { Skin.current.palette.ink3 }
    static let hair = dyn(0xE0D8CC, 0xECE4D8, lightA: 1.0, darkA: 0.13)
    static let hair2 = dyn(0x4B3F31, 0xECE4D8, lightA: 0.09, darkA: 0.07)
    static let hairStrong = dyn(0x4B3F31, 0xECE4D8, lightA: 0.20, darkA: 0.22)

    // MARK: - Domain chips — all resolve from the active skin accent so the whole settings
    // surface recolors with the theme (引擎/系统 used to be fixed teal/brown and stood out).

    static var cLegal: Color { wine }
    static var cLegalBg: Color { wineTint }
    static var cEng: Color { wine }
    static var cEngBg: Color { wineTint }
    static var cSys: Color { wine }
    static var cSysBg: Color { wineTint }

    // MARK: - Status

    static let green = dyn(0x3F8F5B, 0x6BB082)
    static let greenBg = dyn(0x3F8F5B, 0x6BB082, lightA: 0.11, darkA: 0.16)
    static let amber = dyn(0xB0791C, 0xD2A24E)
    static let amberBg = dyn(0xB0791C, 0xD2A24E, lightA: 0.12, darkA: 0.18)

    // MARK: - Metrics (aliases — SkinMetrics is the single value source, issue 309)

    static let radiusWin: CGFloat = SkinMetrics.radiusWindow
    static let radius: CGFloat = SkinMetrics.radiusCard
    static let radiusSmall: CGFloat = SkinMetrics.radiusSmall

    // MARK: - Type scale (309: values reference the adjudicated SkinMetrics scale;
    // headerFont's old 14.5 was absorbed into body 15 per the absorption map)

    static let paneTitle = Font.system(size: SkinMetrics.fsTitle, weight: .semibold)
    static let cardTitle = Font.system(size: SkinMetrics.fsCard, weight: .semibold)
    static let headerFont = Font.system(size: SkinMetrics.fsBody, weight: .semibold)
    static let bodyFont = Font.system(size: SkinMetrics.fsBody)
    static let footnote = Font.system(size: SkinMetrics.fsFoot)
    /// ALL-CAPS group label (`.glabel` in the design).
    static let groupLabel = Font.system(size: SkinMetrics.fsLabel, weight: .bold)
    static let mono = Font.system(size: SkinMetrics.fsFoot, design: .monospaced)

    // MARK: - Dynamic colour plumbing (shared via DynamicColor)

    private static func dyn(_ light: UInt32, _ dark: UInt32,
                           lightA: Double = 1, darkA: Double = 1) -> Color {
        DynamicColor.make(light, dark, lightA: lightA, darkA: darkA)
    }
}

// (`warmForm()` removed — all settings panes now use the WarmCard card style for
//  a single consistent surface; the last 4 Form panes were converted in this pass.)
