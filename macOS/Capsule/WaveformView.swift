import SwiftUI

// Bar height math adapted from Kaze (https://github.com/fayazara/Kaze) — MIT License.
// Driven here by SwiftUI's TimelineView instead of a manual Timer (Swift 6 main-actor safe).

/// Audio-level-driven waveform bars. Two styles: `.pill` (compact, accent-tinted)
/// for the bottom capsule, `.notch` (compact, red) for the Dynamic Island indicator.
/// Bar height = animated sine phase × audio level. Honors Reduce Motion by pausing
/// the timeline (static bars when reduced).
struct WaveformView: View {
    enum Style { case pill, notch }

    var level: Float            // 0...1
    var isRecording: Bool = true
    var style: Style = .pill
    /// Explicit bar colour. nil → the default (skin accent for `.pill`, system red for `.notch`).
    /// The Capsule System passes its (skin-driven) accent so the pill matches the capsule tokens.
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let phaseReferenceCount = 16
    private var barCount: Int { style == .notch ? 5 : 13 }
    private var barColor: Color {
        if let tint { return tint }
        // .pill follows the active skin accent; .notch stays system red.
        return style == .notch ? Color(nsColor: .systemRed) : MacPalette.accent
    }
    private var barWidth: CGFloat { style == .notch ? 3 : 2 }
    private var barSpacing: CGFloat { style == .notch ? 2.5 : 2 }
    private var frameHeight: CGFloat { style == .notch ? 20 : 16 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: style == .notch ? 1.5 : 1)
                        .fill(barColor)
                        .frame(width: barWidth, height: barHeight(for: index, time: time))
                }
            }
            .frame(height: frameHeight)
        }
        .frame(height: frameHeight)
        .accessibilityElement()
        .accessibilityLabel("录音电平")
        .accessibilityValue("\(Int((level * 100).rounded()))%")
    }

    private func barHeight(for index: Int, time: Double) -> CGFloat {
        // Notch uses a spread subset of phases so its 5 bars wave independently.
        let phaseIndex = style == .notch ? min(index * 3, phaseReferenceCount - 1) : index
        let phase = time * 6 + Double(phaseIndex) * 0.5
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = style == .notch ? 4 : 3
        let maxH: CGFloat = style == .notch ? 18 : 16
        // `level` is raw mic RMS×8 clipped to 1 — normal talking volume rarely gets
        // close to 1, so a linear map barely moved the bars (the "flat" look vs.
        // Typeless). pow(level, 0.45) is a display-only perceptual boost that pushes
        // ordinary speech up near the top of the range while staying at 0 in silence.
        let boosted = CGFloat(pow(Double(level), 0.45))
        let amplified = style == .notch ? min(boosted * 1.6, 1) : boosted

        if isRecording {
            let driven = minH + (maxH - minH) * amplified * CGFloat(sine * 0.85 + 0.15)
            return max(minH, driven)
        }
        return minH + (maxH * 0.15) * CGFloat(sine)
    }
}

#Preview {
    VStack(spacing: 24) {
        WaveformView(level: 0.7, style: .pill).padding().background(.black)
        WaveformView(level: 0.7, style: .notch).padding().background(.black)
    }
    .padding()
}
