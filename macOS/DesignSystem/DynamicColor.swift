import SwiftUI
import AppKit

/// Shared light/dark dynamic-colour builder. `Skin` and `SettingsTheme` both
/// resolved their tokens through an identical private `dyn`/`ns` pair; this is
/// the single source so the resolution logic lives in one place.
///
/// A token is an sRGB hex per appearance; the optional alpha lets hairlines and
/// washes carry their own opacity. `MacPalette`'s diff/prosody colours keep
/// their own inline providers (different semantics — not skin-driven).
enum DynamicColor {
    static func make(_ light: UInt32, _ dark: UInt32,
                     lightA: Double = 1, darkA: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ns(isDark ? dark : light, isDark ? darkA : lightA)
        })
    }

    private static func ns(_ hex: UInt32, _ alpha: Double) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha))
    }
}
