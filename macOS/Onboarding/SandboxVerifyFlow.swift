import SwiftUI

/// 来源核验 sandbox flow (hands-on): 划选 a citation (tap-to-select) → press **fn+V** (the real 划词
/// 菜单 trigger) → the shipped 来源核验 demo plays, jumping to 知网 to check 熊伟 的原文. The gesture is
/// real; the CNKI page is the labelled 示例 demo (no live retrieval during onboarding).
struct SandboxVerifyFlow: View {
    @Environment(AppearanceStore.self) private var appearance

    private enum Phase { case selecting, armed, done }
    @State private var phase: Phase = .selecting
    @State private var monitor = SandboxGestureMonitor()

    private let citation = SourceVerificationExamples.xiongWeiPaper.citation

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 12) {
            Text("划选一段引文（点一下模拟选中），按 Fn V 跳知网核对原文。")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                .fixedSize(horizontal: false, vertical: true)
            card(p)
        }
        .onDisappear { monitor.stop() }
    }

    @ViewBuilder private func card(_ p: SkinPalette) -> some View {
        switch phase {
        case .selecting:
            VStack(alignment: .leading, spacing: 14) {
                passage(p, lit: false)
                Button("划选这段引文") { arm() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(p.accent))
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.field))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hairStrong, lineWidth: 1))

        case .armed:
            VStack(alignment: .leading, spacing: 14) {
                passage(p, lit: true)
                HStack(spacing: 9) {
                    ForEach(SandboxGesture.fnV.keycaps, id: \.self) { keycap($0, p) }
                    Text(SandboxGesture.fnV.prompt).font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                }
                Button("直接看示例") { finish() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.accent)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.field))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.accentLine, lineWidth: 1))

        case .done:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("跳转知网核对").font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1).foregroundStyle(p.accent)
                    Text("示例").font(.system(size: 10, weight: .bold)).foregroundStyle(p.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(p.accent))
                    Spacer(minLength: 0)
                    Button("再试一次") { reset() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.ink3)
                }
                FeatureDemoView(kind: .verify)
                    .frame(maxWidth: .infinity).frame(height: 300)
            }
        }
    }

    private func passage(_ p: SkinPalette, lit: Bool) -> some View {
        var s = AttributedString(citation)
        if lit { s.backgroundColor = p.accent.opacity(0.18) }
        return (Text("参见 ").foregroundColor(p.ink) + Text(s) + Text(" 等。").foregroundColor(p.ink))
            .font(.system(size: 14)).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(lit ? p.accentLine : p.hair, lineWidth: 1))
    }

    private func keycap(_ k: String, _ p: SkinPalette) -> some View {
        Text(k).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(p.ink2)
            .frame(minWidth: 40, minHeight: 38).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 9).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.hairStrong, lineWidth: 1))
    }

    // MARK: - Gesture state machine

    private func arm() {
        phase = .armed
        monitor.start(.fnV) { if phase == .armed { finish() } }
    }

    private func finish() {
        phase = .done
        monitor.stop()
    }

    private func reset() {
        phase = .selecting
        monitor.stop()
    }
}
