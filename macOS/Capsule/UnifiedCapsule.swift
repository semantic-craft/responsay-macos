import SwiftUI
import AppKit
import ResponsayCore

/// The Responsay **Capsule System** — *one small capsule, two modes* (Claude Design handoff
/// `Capsule System.dc.html`). The everyday dictation pill and the 任意提问 (Ask-Anything) pill
/// share one compact silhouette, one warm-paper surface and one rhythm; only a small label
/// floating above (ask, while listening) tells them apart.
///
/// Pure presentational: it takes value inputs (never a view model), so both
/// `QuickCaptureViewModel` (dictation) and `VoiceAssistantViewModel` (ask) drive the same
/// anatomy through thin adapters. Colours come from `CapsuleSystemTheme` — **skin-driven**
/// (paper + accent follow the active `Skin`), dark-first, never pure black/blue.
///
/// Anatomy (one row, fixed slots → listening and thinking are both 184×46, so the pill never
/// jumps on the most-watched transition): `[ ✕ 36 · waveform 84 · ✓ 36 ]`, gap 8, pad 6, r23.
/// **No timer, no live transcript inside the pill** — the silhouette never grows mid-capture.
/// Processing swaps to a same-width **thinking pill** with a left→right accent fill.
///
/// The ✕ / ✓ affordances mirror the hotkey controls: ✕ cancels a live capture, ✓ finishes it.
/// Host panels stay non-activating so focus remains in the user's target app.
enum CapsuleMode { case voice, ask }

/// Unified phase across both modes. Each adapter maps its own VM phase onto this set.
/// `followup` = ask asking again after an answer; `searching` = ask running a web search.
enum CapsulePhase { case idle, listening, transcribing, thinking, searching, followup, error, result, copied }

@MainActor
struct UnifiedCapsule: View {
    var mode: CapsuleMode
    var phase: CapsulePhase
    var level: Float = 0
    /// Finished text shown in `.result` (head-truncated). Empty otherwise.
    var liveText: String = ""
    /// Override for the thinking word; empty → derived from `phase` (整理中 / 联网搜索中 / 思考中).
    var thinkingLabel: String = ""
    /// Override for the idle/error status line; empty → the design default for the mode.
    var statusText: String = ""
    /// Identity label floating above the pill (ask mode, while listening). nil = hidden.
    var askLabelText: String?
    /// 联网搜索 model signature (设计稿 Variant B) shown as a chip inside the ask label; nil = hidden.
    var askSource: CapsuleSearchSource?
    var cancelAction: (() -> Void)?
    var finishAction: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The control the pointer is over right now; drives the instant hover label + scale.
    @State private var hoverTip: CapsuleHoverTip?

    private var live: Bool { phase == .listening || phase == .followup }
    private var isThinking: Bool { phase == .transcribing || phase == .thinking || phase == .searching }
    private var hasLeading: Bool { live || phase == .error || phase == .result }
    private var hasTrailing: Bool { live || phase == .error }
    /// Phases whose pill carries tappable controls — exactly when the hover-tip row is reserved.
    private var hasControls: Bool { live || phase == .error }

    var body: some View {
        VStack(spacing: CapsuleSystemTheme.stackGap) {
            // Label stays through listening → thinking → 联网搜索 (no height jump), and hosts the
            // 联网模型署名 chip during search (设计稿 Variant B).
            if mode == .ask, live || isThinking, let askLabelText {
                CapsuleAskLabel(text: askLabelText, source: askSource, reduceMotion: reduceMotion)
            }
            // Reserved headroom for the hover label, kept right above the pill so it hugs the
            // ✕ / ✓ controls. Always present while controls are visible: the host panel measures
            // its size once per phase (never per hover), so the label mustn't change layout when
            // it appears.
            if hasControls { hoverTipRow }
            if isThinking {
                CapsuleThinkingPill(label: resolvedThinkingLabel, reduceMotion: reduceMotion)
            } else {
                recordingPill
            }
        }
        // The recording ⇄ thinking swap is intentionally instant: the host window re-measures
        // and repositions on this change, so an animated swap would fight the resize. Motion
        // lives inside each form (waveform / fill / halo).
    }

    // MARK: - Recording form (idle / listening / followup / error / result)

    /// Explicit pill width per phase — listening and thinking share 184 (never jumps).
    private var pillWidth: CGFloat {
        switch phase {
        case .result: return 216
        case .error:  return 192
        case .idle:   return 150
        default:      return CapsuleSystemTheme.liveWidth   // 164 · listening / followup
        }
    }

    /// Instant Typeless-style label over the hovered control (取消 / 完成 · Fn / 重试 / 复制).
    /// Wider than the pill so the trailing chip can overhang the pill's edge without clipping.
    private var hoverTipRow: some View {
        let width = pillWidth + 2 * tipRowOverhang
        return ZStack {
            if let tip = hoverTip {
                CapsuleHoverTipChip(text: tip.text)
                    .position(x: tip.leadingSide ? tipSlotCenterX : width - tipSlotCenterX,
                              y: tipRowHeight / 2)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: width, height: tipRowHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoverTip)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the buttons already carry accessibility labels
    }

    private var tipRowHeight: CGFloat { 22 }
    private var tipRowOverhang: CGFloat { 16 }
    /// Center of the ✕ / ✓ slot, measured from the row's edge (overhang + pill pad + half slot).
    private var tipSlotCenterX: CGFloat { tipRowOverhang + CapsuleSystemTheme.outerPad + CapsuleSystemTheme.slotSide / 2 }

    private var recordingPill: some View {
        HStack(spacing: CapsuleSystemTheme.slotGap) {
            if hasLeading { leadingSlot.frame(width: CapsuleSystemTheme.slotSide) }
            centerSlot
            if hasTrailing { trailingSlot.frame(width: CapsuleSystemTheme.slotSide) }
        }
        .padding(.horizontal, CapsuleSystemTheme.outerPad)
        // Explicit size: NSHostingView.fittingSize returns 0 for this view, so the host panel
        // must not rely on measurement — the pill carries its own definite size.
        .frame(width: pillWidth, height: CapsuleSystemTheme.pillHeight)
        .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        // Clip the frosted backdrop to the capsule. Without this, the material's NSVisualEffectView
        // is un-clipped and its union with the floating label reads as a rectangular "outer frame"
        // (设计稿 核心修复). The dictation pill is single-element so it never showed the artifact.
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .opacity(phase == .idle ? 0.62 : 1)
    }

    /// Leading cue: ✕ cancel (live) / ⚠ (error) / ✓ result.
    @ViewBuilder private var leadingSlot: some View {
        if live {
            controlButton(systemName: "xmark", fg: CapsuleSystemTheme.ink2, bg: CapsuleSystemTheme.chip,
                          glyphSize: 14, help: "取消", tipLeading: true, action: cancelAction)
                .accessibilityLabel("取消")
        } else if phase == .error {
            glyphBadge(systemName: "exclamationmark.triangle.fill", fg: CapsuleSystemTheme.err,
                       bg: CapsuleSystemTheme.errSoft, diameter: 28, glyphSize: 13)
                .accessibilityLabel("出错")
        } else if phase == .result {
            glyphBadge(systemName: "checkmark", fg: CapsuleSystemTheme.accentInk,
                       bg: CapsuleSystemTheme.accent, diameter: 24, glyphSize: 12, weight: .bold)
                .accessibilityHidden(true)
        }
    }

    /// Center: waveform (live) → result text → idle/error status.
    @ViewBuilder private var centerSlot: some View {
        if live {
            WaveformView(level: level, isRecording: true, style: .pill, tint: CapsuleSystemTheme.accentText)
                .frame(width: CapsuleSystemTheme.slotWave)
        } else if phase == .result {
            Text(liveText)
                .font(.system(size: 13))
                .foregroundStyle(CapsuleSystemTheme.ink)
                .lineLimit(1)
                .truncationMode(.head)   // keep the newest words, like macOS dictation
                .frame(maxWidth: 212, alignment: .leading)
        } else {  // idle / error
            Text(resolvedStatusText)
                .font(.system(size: 13))
                .foregroundStyle(phase == .error ? CapsuleSystemTheme.err : CapsuleSystemTheme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .fixedSize()
        }
    }

    /// Trailing action: ✓ finish (live) / ↻ retry (error).
    @ViewBuilder private var trailingSlot: some View {
        if live {
            controlButton(systemName: "checkmark", fg: CapsuleSystemTheme.accentInk, bg: CapsuleSystemTheme.accent,
                          glyphSize: 15, weight: .bold, glow: true, help: "完成 · Fn", action: finishAction)
                .accessibilityLabel("完成")
        } else if phase == .error {
            controlButton(systemName: "arrow.clockwise", fg: CapsuleSystemTheme.err, bg: CapsuleSystemTheme.errSoft,
                          glyphSize: 16, help: "重试", action: finishAction)
                .accessibilityLabel("重试")
        }
    }

    // MARK: - Derived labels

    private var resolvedThinkingLabel: String {
        if !thinkingLabel.isEmpty { return thinkingLabel }
        switch phase {
        case .transcribing: return "整理中"
        case .searching:    return "联网搜索中"
        default:            return "思考中"
        }
    }

    private var resolvedStatusText: String {
        if !statusText.isEmpty { return statusText }
        if phase == .error { return mode == .ask ? "暂时无法回答" : "识别失败 · 请重试" }
        if phase == .idle { return "Fn 听写 · ⌥ 提问" }
        return ""
    }

    // MARK: - Pieces

    /// A 36pt circular control button (tappable). `glow` adds the accent halo under the ✓.
    /// `help` doubles as the instant hover label; `tipLeading` picks which slot it floats over.
    @ViewBuilder
    private func controlButton(systemName: String, fg: Color, bg: Color, glyphSize: CGFloat,
                               weight: Font.Weight = .regular, glow: Bool = false,
                               help: String = "", tipLeading: Bool = false,
                               action: (() -> Void)?) -> some View {
        let content = ZStack {
            Circle().fill(bg)
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: weight))
                .foregroundStyle(fg)
        }
        .frame(width: CapsuleSystemTheme.slotSide, height: CapsuleSystemTheme.slotSide)
        .shadow(color: glow ? CapsuleSystemTheme.glow : .clear, radius: glow ? 8 : 0, y: glow ? 4 : 0)

        if let action {
            Button(action: action) {
                // Visual icon stays 30; the tappable zone fills the pill height (36) + ±4px buffer
                // → 38×36 hit target (设计稿 §4.5 命中区). Overflows into the slot gap, so the
                // pill's layout width stays 160 while mis-clicks near the edge still register.
                // (设计稿 §4.5 also specs a keyboard focus ring — intentionally NOT implemented:
                // the host panel is non-activating so it never holds keyboard focus; Esc/Fn run via
                // global hotkeys, so there is no focusable element to ring.)
                content
                    .frame(width: CapsuleSystemTheme.slotSide + 8, height: CapsuleSystemTheme.pillHeight)
                    .contentShape(Rectangle())
            }
                // Self-drawn instant label instead of `.help()`: the system tooltip needs ~1.5 s
                // of dwell and rarely fires at all on the click-through indicator panel.
                .buttonStyle(CapsuleControlButtonStyle(hovered: hoverTip?.text == help,
                                                       reduceMotion: reduceMotion))
                .onHover { hovering in
                    if hovering {
                        hoverTip = CapsuleHoverTip(text: help, leadingSide: tipLeading)
                    } else if hoverTip?.text == help {
                        hoverTip = nil   // guard: don't clear a neighbour's fresher hover
                    }
                }
        } else {
            content
        }
    }

    /// A small non-interactive glyph badge (⚠ error, ✓ result), centered in the 36pt slot.
    private func glyphBadge(systemName: String, fg: Color, bg: Color, diameter: CGFloat,
                            glyphSize: CGFloat, weight: Font.Weight = .regular) -> some View {
        ZStack {
            Circle().fill(bg)
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: weight))
                .foregroundStyle(fg)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Thinking pill (same width as listening, left→right accent fill)

private struct CapsuleThinkingPill: View {
    let label: String
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0.06

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(CapsuleSystemTheme.fill)
                .frame(width: CapsuleSystemTheme.liveWidth * progress, height: CapsuleSystemTheme.pillHeight)
            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .tracking(0.7)               // ≈ letter-spacing .05em
                .foregroundStyle(CapsuleSystemTheme.ink)
                .frame(maxWidth: .infinity)
        }
        .frame(width: CapsuleSystemTheme.liveWidth, height: CapsuleSystemTheme.pillHeight)
        .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .onAppear {
            if reduceMotion {
                progress = 0.7   // jump to a stable fill instead of sweeping
            } else {
                withAnimation(.timingCurve(0.3, 0.55, 0.35, 1, duration: 1.6)) { progress = 1.0 }
            }
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Floating ask-identity label (pulse dot + soft accent halo)

private struct CapsuleAskLabel: View {
    let text: String
    var source: CapsuleSearchSource? = nil
    let reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        HStack(spacing: 6) {
            CapsulePulseDot(reduceMotion: reduceMotion)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CapsuleSystemTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
            if let source { CapsuleSourceChip(source: source) }
        }
        .padding(.horizontal, 13)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))   // clip frost to the pill — no rectangular frame
        .overlay(Capsule(style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .shadow(color: CapsuleSystemTheme.glow.opacity(glow ? 0.7 : 0.4), radius: glow ? 16 : 11)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: glow)
        .onAppear { if !reduceMotion { glow = true } }
        .fixedSize()
    }
}

/// 联网搜索模型署名 chip(设计稿 ask-anything-capsule · Variant B):9pt 单字纹章 + 模型名,
/// 嵌在浮标签里,让用户一眼看出是哪个 AI 在联网搜索。取色随当前皮肤(胶囊纸面 + 皮肤强调色)。
private struct CapsuleSourceChip: View {
    let source: CapsuleSearchSource

    var body: some View {
        HStack(spacing: 4) {
            Text(source.monogram)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(CapsuleSystemTheme.surface)
                .frame(width: 9, height: 9)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(CapsuleSystemTheme.accentText))
            Text(source.name)
                .font(.system(size: 10))
                .foregroundStyle(CapsuleSystemTheme.ink)
                .lineLimit(1)
        }
        .padding(.leading, 5).padding(.trailing, 6).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(CapsuleSystemTheme.accentSoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("联网模型 \(source.name)")
    }
}

// MARK: - Accent pulse dot (ask label)

private struct CapsulePulseDot: View {
    let reduceMotion: Bool
    @State private var big = false

    var body: some View {
        Circle()
            .fill(CapsuleSystemTheme.accentText)
            .frame(width: 6, height: 6)
            .shadow(color: CapsuleSystemTheme.accentText.opacity(0.6), radius: 4)
            .scaleEffect(big ? 1.12 : 0.8)
            .opacity(big ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: big)
            .onAppear { if !reduceMotion { big = true } }
            .accessibilityHidden(true)
    }
}
