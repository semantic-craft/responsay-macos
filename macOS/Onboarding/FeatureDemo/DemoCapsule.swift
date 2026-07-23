import SwiftUI

/// A non-interactive replica of the bottom-center capsule (`CapsuleView` pill form) for the
/// onboarding demos. Renders the `listening` (waveform + rec dot + timer) and `thinking`
/// (spinner) states from a `DemoFrameState`; entrance opacity/offset are applied by the caller.
struct DemoCapsule: View {
    let state: DemoFrameState

    var body: some View {
        HStack(spacing: 10) {
            switch state.pillMode {
            case .listening:
                BreathingDot()
                WaveformView(level: state.waveActive ? 0.72 : 0.22,
                             isRecording: state.waveActive,
                             style: .pill)
                    .frame(width: 52)
                label
                if !state.pillTime.isEmpty {
                    Text(state.pillTime)
                        .font(.system(.caption, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .thinking:
                ProgressView().controlSize(.small)
                label
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background {
            ZStack {
                Capsule(style: .continuous).fill(.regularMaterial)
                Capsule(style: .continuous).fill(Color(nsColor: .windowBackgroundColor).opacity(0.54))
            }
        }
        .overlay(Capsule(style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .fixedSize()
    }

    private var label: some View {
        Text(state.pillLabel)
            .font(.system(size: SkinMetrics.fsFoot, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

/// Breathing red recording dot — mirrors `CapsuleView`'s private `RecordingDot`.
private struct BreathingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemRed))
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.0 : 0.7)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}
