import SwiftUI

/// One auto-looping feature demo: a scripted UI simulation (host mock + simulated capsule + review
/// panel) of a single responsay feature. Motion is driven entirely by the pure
/// `DemoTimeline.state(for:at:)`, sampled on a `TimelineView` clock; Reduce Motion shows one static
/// "result" frame.
struct FeatureDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: FeatureDemoKind

    private var script: FeatureDemoScript { .script(for: kind) }

    var body: some View {
        Group {
            if reduceMotion {
                frame(DemoTimeline.state(for: kind, at: kind.reducedTimeMs, script: script))
            } else {
                TimelineView(.animation) { context in
                    frame(DemoTimeline.state(for: kind, at: loopTime(context.date), script: script))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
    }

    /// Shared wall clock → per-demo loop position (ms), so the four demos run on staggered phases.
    private func loopTime(_ date: Date) -> Double {
        let ms = date.timeIntervalSinceReferenceDate * 1000 + kind.offsetMs
        return ms.truncatingRemainder(dividingBy: kind.durationMs)
    }

    @ViewBuilder private func frame(_ s: DemoFrameState) -> some View {
        DemoHostWindow(script: script, state: s)
            .overlay(alignment: .topTrailing) {
                if s.hotkeyOpacity > 0.01 {
                    HotkeyBadge(text: s.hotkeyText)
                        .scaleEffect(s.hotkeyScale)
                        .offset(y: CGFloat(s.hotkeyOffsetY))
                        .opacity(s.hotkeyOpacity)
                        .padding(SkinMetrics.sp4)
                }
            }
            .overlay(alignment: .topLeading) {
                if s.menuOpacity > 0.01 {
                    DemoSwipeMenu(highlight: s.menuHighlight)
                        .opacity(s.menuOpacity)
                        .padding(.leading, SkinMetrics.sp4)
                        .padding(.top, 72)
                }
            }
            .overlay {
                if s.searchPageOpacity > 0.01 {
                    if case let .anchors(items) = script.resultContent {
                        DemoSearchPageOverlay(items: items, state: s)
                            .opacity(s.searchPageOpacity)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if s.contentReplaced || s.verifiedSourceRevealCount > 0 || s.urlRevealCount > 0 {
                    DemoOutcomeToast(text: kind.outcomeToast)
                        .opacity(max(0.82, s.flashOpacity))
                        .padding(SkinMetrics.sp3)
                }
            }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    DemoResultPanel(script: script, state: s)
                        .offset(y: CGFloat(s.panelOffsetY))
                        .opacity(s.panelOpacity)
                        .padding(.bottom, 74)
                        .padding(.horizontal, SkinMetrics.sp3)
                    DemoCapsule(state: s)
                        .scaleEffect(s.pillScale, anchor: .bottom)
                        .offset(y: CGFloat(s.pillOffsetY))
                        .opacity(s.pillOpacity)
                        .padding(.bottom, 16)
                }
                .allowsHitTesting(false)
            }
    }
}

/// A short result confirmation shared by every demo, so each loop has a visible
/// "the action landed" moment in addition to the scripted host content.
private struct DemoOutcomeToast: View {
    @Environment(AppearanceStore.self) private var appearance
    let text: String

    var body: some View {
        let p = appearance.palette
        HStack(spacing: SkinMetrics.sp1) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
        }
        .foregroundStyle(p.onAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(p.accentDeep))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
    }
}

/// The floating hotkey hint (⌥R / 轻点 Fn …) shown top-right of a demo.
private struct HotkeyBadge: View {
    @Environment(AppearanceStore.self) private var appearance
    let text: String

    var body: some View {
        let p = appearance.palette
        Text(text)
            .font(.system(size: SkinMetrics.fsLabel, weight: .bold, design: .monospaced))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(p.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.11), radius: 8, y: 4)
    }
}
