import SwiftUI

/// The per-skin decoration and phase choreography that `CapsuleTokens` can't express as colour:
/// armour bevel, psychoframe lattice, the mono-eye, and the running edge arc.
///
/// Everything here is purely presentational and takes value inputs, matching `UnifiedCapsule`'s
/// contract. Nothing draws for `.followSkin` — the default install renders exactly what it did
/// before this axis existed.

// MARK: - Chrome overlay (drawn inside the pill, under the ink)

/// Skin-specific surface treatment, clipped to the pill.
struct CapsuleSkinChrome: View {
    let skin: CapsuleSkin

    var body: some View {
        switch skin {
        case .followSkin:
            EmptyView()
        case .zaku:
            // 装甲上缘高光 + 下缘阴影 — the bevel is what stops the wine surface reading flat.
            // Stops are fractions of the fixed 36pt pill height (9pt and 10pt).
            ZStack {
                LinearGradient(stops: [.init(color: .white.opacity(0.20), location: 0),
                                       .init(color: .white.opacity(0), location: 0.25)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0),
                                       .init(color: .black.opacity(0), location: 0.28)],
                               startPoint: .bottom, endPoint: .top)
            }
            .allowsHitTesting(false)
        case .psychoFrame:
            // 斜向晶格切面 — screen-blended so it reads as light passing through, not paint on top.
            Canvas { ctx, size in
                let spacing: CGFloat = 9
                let angle = Angle.degrees(114)
                let reach = size.width + size.height
                var path = Path()
                var offset = -reach
                while offset < reach {
                    path.move(to: CGPoint(x: offset, y: -reach))
                    path.addLine(to: CGPoint(x: offset, y: reach))
                    offset += spacing
                }
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: angle)
                ctx.stroke(path, with: .color(.white.opacity(0.09)), lineWidth: 1)
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 单眼 (MS-06S)

/// The mono-eye that replaces the waveform while 录音中: a lens patrolling a dark slot, its
/// brightness driven by the mic level. It *looks at you* instead of drawing your voice — the whole
/// point of the skin, so it occupies the same 72 × 16 slot the waveform did.
struct MonoEyeView: View {
    var level: Float                       // 0...1
    var tint: Color
    var glow: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slotWidth: CGFloat = CapsuleSystemTheme.slotWave
    private let slotHeight: CGFloat = 16
    private let lensSide: CGFloat = 15

    var body: some View {
        // Same perceptual boost as WaveformView: raw RMS rarely approaches 1, so ordinary speech
        // would barely move the lens on a linear map.
        let boosted = CGFloat(pow(Double(max(0, min(1, level))), 0.45))

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let span = slotWidth - lensSide
            let x = reduceMotion ? span / 2 : (sin(t * 1.15) * 0.5 + 0.5) * span

            ZStack(alignment: .leading) {
                lens
                    .opacity(0.55 + 0.45 * boosted)
                    .offset(x: x)
            }
            .frame(width: slotWidth, height: slotHeight, alignment: .leading)
        }
        .frame(width: slotWidth, height: slotHeight)
        .background(socket)
        .overlay(scanlines)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("录音电平")
        .accessibilityValue("\(Int((level * 100).rounded()))%")
    }

    private var socket: some View {
        LinearGradient(colors: [Color(red: 0.08, green: 0.04, blue: 0.06),
                                Color(red: 0.04, green: 0.02, blue: 0.03)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var lens: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: .white, location: 0),
                                         .init(color: tint, location: 0.30),
                                         .init(color: tint.opacity(0), location: 0.72)],
                                 center: UnitPoint(x: 0.5, y: 0.45),
                                 startRadius: 0, endRadius: lensSide * 0.72))
            .frame(width: lensSide, height: lensSide)
            .shadow(color: glow, radius: 5)
    }

    /// CRT-style horizontal ruling — static, so it stays outside the timeline.
    private var scanlines: some View {
        Canvas { ctx, size in
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 2
            }
            ctx.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// The mono-eye in its 30pt socket, used in every phase **except** 录音中 — the `.signature`
/// choreography's core claim is that the eye never leaves. It takes over the slot that
/// `.fillSweep` gives to the ✓ / ⚠ badges, so the eye itself has to carry "done" and "failed".
struct MonoEyeBadge: View {
    let phase: CapsulePhase
    let tint: Color
    let glow: Color
    let alarmTint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var isAlarm: Bool { phase == .error }
    private var lensColor: Color { isAlarm ? alarmTint : tint }

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.10, green: 0.05, blue: 0.07),
                                                  Color(red: 0.03, green: 0.02, blue: 0.03)],
                                         center: UnitPoint(x: 0.5, y: 0.40),
                                         startRadius: 0, endRadius: CapsuleSystemTheme.slotSide * 0.6))
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0),
                                             .init(color: lensColor, location: 0.32),
                                             .init(color: lensColor.opacity(0), location: 0.74)],
                                     center: UnitPoint(x: 0.5, y: 0.45),
                                     startRadius: 0, endRadius: 9))
                .frame(width: 13, height: 13)
                .shadow(color: isAlarm ? alarmTint.opacity(0.9) : glow, radius: 4)
                .scaleEffect(x: 1, y: squint, anchor: .center)
                .scaleEffect(breathScale)
                .opacity(lensOpacity)
        }
        .frame(width: CapsuleSystemTheme.slotSide, height: CapsuleSystemTheme.slotSide)
        .clipShape(Circle())
        .animation(motion, value: animating)
        .onAppear { if !reduceMotion { animating = true } }
        .accessibilityLabel(accessibilityText)
    }

    /// 结果：眯成一条缝 —— the squint *is* the ✓ this choreography gave up.
    private var squint: CGFloat { phase == .result ? 0.22 : 1 }

    /// 思考：呼吸；出错：急闪；其余定住。
    private var breathScale: CGFloat {
        guard phase == .thinking, animating else { return 1 }
        return 1.06
    }
    private var lensOpacity: Double {
        switch phase {
        case .idle:     return 0.28
        case .thinking: return animating ? 1 : 0.5
        case .error:    return animating ? 0.25 : 1
        default:        return 1
        }
    }

    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        switch phase {
        case .thinking: return .easeInOut(duration: 0.75).repeatForever(autoreverses: true)
        case .error:    return .easeInOut(duration: 0.25).repeatForever(autoreverses: true)
        default:        return nil
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .error:  return "出错"
        case .result: return "完成"
        default:      return "待命"
        }
    }
}

// MARK: - 边缘能量环 (Psycho-Frame)

/// A bright arc running the pill's outline, the `.edgeArc` choreography's answer to the progress
/// fill. Drawn as a single dash whose `dashPhase` animates by one full perimeter — trim can't wrap
/// past 1.0, dash phase can, so the arc runs continuously instead of blinking out at the seam.
///
/// Rendered as an overlay *after* the pill's `clipShape`, so it is never clipped; the shape is
/// inset by half the line width so the stroke sits fully inside the silhouette.
struct CapsuleEdgeArc: View {
    enum Kind { case running, solid, alarm }

    let kind: Kind
    let width: CGFloat
    let color: Color
    let glow: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    private let lineWidth: CGFloat = 2.5
    private var height: CGFloat { CapsuleSystemTheme.pillHeight }

    /// Capsule perimeter at the inset path: two straight flanks + one full circle of the end caps.
    private var perimeter: CGFloat {
        let w = width - lineWidth, h = height - lineWidth
        return 2 * max(0, w - h) + .pi * h
    }

    var body: some View {
        Capsule(style: .continuous)
            .inset(by: lineWidth / 2)
            .stroke(strokeColor, style: style)
            .shadow(color: glow, radius: 4)
            .opacity(alarmOpacity)
            .animation(alarmMotion, value: phase)
            .onAppear { start() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var strokeColor: Color { kind == .alarm ? color : color }

    private var style: StrokeStyle {
        switch kind {
        case .running:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                               dash: [perimeter * 0.22, perimeter * 0.78], dashPhase: phase)
        case .solid, .alarm:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        }
    }

    /// The running arc animates `dashPhase`; the alarm re-uses the same state to blink.
    private var alarmOpacity: Double {
        guard kind == .alarm else { return 1 }
        return phase == 0 ? 1 : 0.2
    }

    private var alarmMotion: Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .running: return .linear(duration: 1.5).repeatForever(autoreverses: false)
        case .alarm:   return .easeInOut(duration: 0.28).repeatForever(autoreverses: true)
        case .solid:   return nil
        }
    }

    private func start() {
        guard !reduceMotion else {
            // Reduce Motion: a static three-quarter arc still reads as "working", without travel.
            if kind == .running { phase = perimeter * 0.5 }
            return
        }
        switch kind {
        case .running: phase = -perimeter
        case .alarm:   phase = 1
        case .solid:   break
        }
    }
}
