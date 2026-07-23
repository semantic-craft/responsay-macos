import SwiftUI
import AppKit

/// macOS brand + semantic tokens, browser-confirmed (§7 review-locked). Parallels iOS `Theme`.
///
/// The **brand accent is skin-driven** (`Skin.current`, default 荔园红) — it replaced the former
/// Apple-green. The diff/prosody colours below stay *semantic* (green = added, red = removed,
/// green = pitch contour) and are intentionally **not** skinned. See ADR-0026.
enum MacPalette {
    /// Brand accent from the active `Skin` (default 荔园红). Was Apple green #34C759/#30D158.
    static var accent: Color { Skin.current.palette.accent }
    /// Ink/glyph on the accent (prominent-button label) — from the active skin (`onAccent`).
    static var accentInk: Color { Skin.current.palette.onAccent }
    /// Inserted-word green in the idiomatic headline. Bright #7BE6A4 dark; deeper #1F8F4E light (≥4.5:1 on white).
    static let inserted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 123/255, green: 230/255, blue: 164/255, alpha: 1) // #7BE6A4
            : NSColor(red: 31/255,  green: 143/255, blue: 78/255,  alpha: 1) // #1F8F4E
    })
    /// Deleted-word color for the "你说的" diff line. Bright #FF7A70 dark; deeper #C7372C light.
    static let deleted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 255/255, green: 122/255, blue: 112/255, alpha: 1) // #FF7A70
            : NSColor(red: 199/255, green: 55/255,  blue: 44/255,  alpha: 1) // #C7372C
    })
    /// 中式→美式 block tint: rgba(70,209,127,0.08) + 2px #46D17F left border. Deeper #1F8F4E in light for text contrast.
    static let prosody = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 70/255,  green: 209/255, blue: 127/255, alpha: 1) // #46D17F
            : NSColor(red: 31/255,  green: 143/255, blue: 78/255,  alpha: 1) // #1F8F4E
    })
}
