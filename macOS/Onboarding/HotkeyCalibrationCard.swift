import SwiftUI

/// 设快捷键 real keypress calibration (spec §4.1): press the chosen primary key and watch the
/// on-screen keycap light up 荔园红 — genuine proof the OS delivers the key to the app. Inline
/// confidence widget; the wizard footer still drives step advance.
struct HotkeyCalibrationCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let scheme: ShortcutScheme

    @State private var calibration = HotkeyCalibration()
    @State private var monitor = HotkeyCalibrationMonitor()

    private var lit: Bool { calibration.state != .idle }

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("试一下：按一下你的\(scheme == .fn ? "" : "组合")快捷键")
                    .font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
                Text("按下时，下面的按键会变红——这说明系统把按键交给了 Responsay。")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
            }

            HStack(spacing: 9) {
                ForEach(scheme.keycaps, id: \.self) { keycap($0, p) }
                Spacer(minLength: 0)
            }

            stateRow(p)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.field))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
            .strokeBorder(lit ? p.accentLine : p.hairStrong, lineWidth: 1))
        .onAppear { startMonitor() }
        .onDisappear { monitor.stop() }
        .onChange(of: scheme) { _, _ in
            calibration.reset()
            startMonitor()
        }
    }

    private func startMonitor() {
        monitor.start(scheme: scheme) { calibration.keyPressed() }
    }

    private func keycap(_ k: String, _ p: SkinPalette) -> some View {
        Text(k)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundStyle(lit ? p.onAccent : p.ink2)
            .frame(minWidth: 46).frame(height: 48).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(lit ? p.accent : p.card2))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lit ? .clear : p.hairStrong, lineWidth: 1))
            .scaleEffect(lit ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: calibration.state)
    }

    @ViewBuilder private func stateRow(_ p: SkinPalette) -> some View {
        switch calibration.state {
        case .idle:
            Label("等待按键…", systemImage: "keyboard")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
        case .detected:
            HStack(spacing: 10) {
                Text("看到它变红了吗？").font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                Spacer(minLength: 0)
                Button("不行，换一个") { calibration.reset() }
                    .buttonStyle(.plain).font(.system(size: 12))
                    .foregroundStyle(p.ink3)
                Button("是的，就用这个") { calibration.confirm() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(p.accent))
            }
        case .confirmed:
            Label("已就绪，快捷键可用", systemImage: "checkmark.circle.fill")
                .font(.system(size: SkinMetrics.fsFoot, weight: .semibold))
                .foregroundStyle(MacPalette.inserted)
        }
    }
}
