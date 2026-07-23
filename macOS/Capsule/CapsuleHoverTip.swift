import SwiftUI

// The capsule's hover-tip unit (Typeless-parity): an instant self-drawn label above the
// hovered ✕ / ✓ control, plus the immediate hover/press feedback for those controls.
// Replaces `.help()` — the system tooltip needs ~1.5 s of dwell and, on the click-through
// indicator panel, often never receives the tracking events that would show it at all.

/// Which control a `UnifiedCapsule` is currently labelling: the text to show and
/// whether it sits over the leading (✕) or trailing (✓ / ↻ / 📋) slot.
struct CapsuleHoverTip: Equatable {
    let text: String
    let leadingSide: Bool
}

/// The label chip itself — inverse of the pill (warm ink surface, paper text) so it reads
/// instantly in both appearances without going pure black.
struct CapsuleHoverTipChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(CapsuleSystemTheme.surface)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CapsuleSystemTheme.ink))
            .shadow(color: CapsuleSystemTheme.shadow.opacity(0.5), radius: 6, y: 3)
            .fixedSize()
    }
}

/// Immediate pointer feedback for the capsule's circular controls: grow slightly on hover,
/// sink on press. The old plain style gave no visual acknowledgement at all, which read as
/// lag even when the click registered.
struct CapsuleControlButtonStyle: ButtonStyle {
    var hovered: Bool
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.9 : (hovered ? 1.08 : 1)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
    }
}
