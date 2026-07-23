import SwiftUI

/// Hands-on 语音翻译 / 任意提问 in the sandbox. The full product gesture, usable even with no model
/// configured ("哪怕假结果"):
///   - 语音翻译: press Fn Shift → "speak" the suggested line → press **Fn** to end → 示例 译文.
///   - 任意提问: 划选 a passage first (`selectionPassage`, tap-to-select) → Fn Space → "speak" →
///     Fn end → 示例 答卡 about that passage.
/// Listening is simulated and the result is canned — and since it's the translation/answer of the
/// suggested line the user reads, it stays coherent. Button fallbacks ("直接看示例" / "结束并看结果")
/// cover key-detection misses.
struct SandboxSpokenFlow: View {
    @Environment(AppearanceStore.self) private var appearance

    let startGesture: SandboxGesture      // .fnShift / .fnSpace
    let instruction: String
    let spokenExample: String             // Chinese to read aloud
    let listeningLabel: String            // "正在听中文 · 再按 Fn 结束"
    let thinkingLabel: String             // "翻译中…" / "整理回答…"
    let resultLabel: String               // "译文（示例）" / "回答（示例）"
    let resultText: String                // canned English / answer
    var serifResult: Bool = false
    /// 任意提问 only: a passage the user "划选" before asking (tap-to-select). nil → no select phase.
    var selectionPassage: String? = nil

    private enum Phase { case selecting, idle, listening, thinking, done }
    @State private var phase: Phase = .idle
    @State private var monitor = SandboxGestureMonitor()
    @State private var armed = false
    @State private var didSelect = false

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 12) {
            Text(instruction)
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                .fixedSize(horizontal: false, vertical: true)
            card(p)
        }
        .onAppear { startIdle() }
        .onDisappear { monitor.stop() }
    }

    @ViewBuilder private func card(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .selecting:
                Text("划选下面这段（点一下模拟选中）：")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                passage(p, lit: false)
                Button("划选这段") { select() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(p.accent))

            case .idle:
                selectedBanner(p)
                HStack(spacing: 9) {
                    ForEach(startGesture.keycaps, id: \.self) { keycap($0, p) }
                    Text(startGesture.prompt).font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                }
                sayLine(p)
                Button("直接看示例") { phase = .done; monitor.stop() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.accent)

            case .listening:
                selectedBanner(p)
                HStack(spacing: 10) {
                    WaveBars(color: p.accent)
                    Text(listeningLabel).font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                }
                sayLine(p)
                Button("结束并看结果") { endListening() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.accent)

            case .thinking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(thinkingLabel).font(.system(size: SkinMetrics.fsBody)).foregroundStyle(p.ink2)
                    Spacer(minLength: 0)
                }

            case .done:
                HStack(spacing: 8) {
                    Text(resultLabel).font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1).foregroundStyle(p.accent)
                    Text("示例").font(.system(size: 10, weight: .bold)).foregroundStyle(p.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(p.accent))
                    Spacer(minLength: 0)
                    Button("再试一次") { startIdle() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.ink3)
                }
                Text(resultText)
                    .font(serifResult ? .system(size: 14, design: .serif) : .system(size: 14))
                    .foregroundStyle(p.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.field))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
            .strokeBorder(phase == .listening ? p.accentLine : p.hairStrong, lineWidth: 1))
    }

    /// The selected passage, optionally lit (划选后高亮)。
    private func passage(_ p: SkinPalette, lit: Bool) -> some View {
        var s = AttributedString(selectionPassage ?? "")
        if lit { s.backgroundColor = p.accent.opacity(0.18) }
        return Text(s)
            .font(.system(size: 14)).foregroundStyle(p.ink).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lit ? p.accentLine : p.hair, lineWidth: 1))
    }

    /// One-line "已划选：…" reminder once selected, shown across idle/listening (任意提问 only).
    @ViewBuilder private func selectedBanner(_ p: SkinPalette) -> some View {
        if didSelect, let passage = selectionPassage {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor").font(.system(size: 10)).foregroundStyle(p.accent)
                Text("已划选：" + passage).font(.system(size: 11)).foregroundStyle(p.ink2).lineLimit(1)
            }
        }
    }

    private func sayLine(_ p: SkinPalette) -> some View {
        Text("试着说：\(spokenExample)")
            .font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func keycap(_ k: String, _ p: SkinPalette) -> some View {
        Text(k).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(p.ink2)
            .frame(minWidth: 40, minHeight: 38).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 9).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.hairStrong, lineWidth: 1))
    }

    // MARK: - Gesture state machine

    /// 任意提问 starts in `.selecting` until the user 划选s; everything else (and 再试一次) goes
    /// straight to `.idle` and arms the start key.
    private func startIdle() {
        armed = false
        if selectionPassage != nil && !didSelect {
            phase = .selecting
            monitor.stop()      // don't arm the start key until a passage is 划选ed
        } else {
            phase = .idle
            monitor.start(startGesture) { beginListening() }
        }
    }

    private func select() {
        didSelect = true
        phase = .idle
        monitor.start(startGesture) { beginListening() }
    }

    private func beginListening() {
        guard phase == .idle else { return }
        phase = .listening
        armed = false
        // After start, watch for the Fn end-tap — but ignore the start chord's lingering Fn for a
        // beat so releasing Fn Shift doesn't instantly "end".
        monitor.start(.fnTap) { if armed { endListening() } }
        Task { try? await Task.sleep(for: .seconds(0.6)); armed = true }
    }

    private func endListening() {
        guard phase == .listening else { return }
        monitor.stop()
        phase = .thinking
        Task { try? await Task.sleep(for: .seconds(0.9)); if phase == .thinking { phase = .done } }
    }
}

/// Simulated listening waveform (no real capture — the result is a canned 示例).
private struct WaveBars: View {
    let color: Color
    @State private var up = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 3, height: up ? 16 : 6)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.1), value: up)
            }
        }
        .frame(height: 18)
        .onAppear { up = true }
    }
}
