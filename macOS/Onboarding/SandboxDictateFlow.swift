import ResponsayCore
import SwiftUI

/// 听写 sandbox flow — **real** (model A): the Apple key-free recognizer streams your actual words
/// into the 模拟编辑器. Falls back to a scripted simulation when speech is denied/unavailable, so the
/// step never dead-ends (issue 312). Extracted from the old monolithic SandboxStepView.
struct SandboxDictateFlow: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel
    let speechAuthorized: Bool?

    @State private var phase: Phase = .idle
    @State private var simulatedText = ""
    @State private var capsuleText = ""
    @State private var dictation = SandboxDictation()
    @State private var realDictationFailed = false
    @State private var isRecording = false

    enum Phase { case idle, listening, thinking, inserting, done }

    private var realModeAvailable: Bool { speechAuthorized == true && !realDictationFailed }
    private var script: SandboxDemoScript { .demo(for: model.usage) }

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 14) {
            Text(realModeAvailable
                 ? "来真的：点一下开始说话，再点一下结束，看着它出现在编辑器里（正式用时改成点按 \(model.shortcutScheme == .fn ? "Fn" : "组合键")）。"
                 : "看一遍唤起 → 说话 → 上屏；授权语音识别后还能用自己的声音试。")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)

            HStack(spacing: 12) {
                if phase == .done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(MacPalette.inserted)
                    Text("成了！这就是真实的听写。").font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
                    Button("再说一句") { resetForRetry() }.buttonStyle(.bordered).controlSize(.small)
                } else if realModeAvailable {
                    tapDictationButton
                    if phase == .idle {
                        Text("比如：\(script.suggestion)").font(.system(size: 12)).foregroundStyle(p.ink3).lineLimit(1)
                        Button("看模拟演示") { simulateInteraction() }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.ink3)
                    }
                } else {
                    Text("试着说：\(script.suggestion)").font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink).lineLimit(1)
                    if phase == .idle {
                        Button("模拟按下") { simulateInteraction() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
            .onAppear { simulatedText = ""; capsuleText = ""; phase = .idle }

            editor(p)
        }
        // Release the mic if the user advances (下一个) or closes onboarding mid-recording —
        // 结束并定稿 is no longer the only path that stops the engine.
        .onDisappear {
            dictation.cancel()
            isRecording = false
        }
    }

    private func editor(_ p: SkinPalette) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading) {
                Text("模拟编辑器").font(.system(size: 11, weight: .bold)).foregroundStyle(p.ink3).padding(.bottom, 4)
                Text(simulatedText.isEmpty ? "光标在这里闪烁..." : simulatedText)
                    .font(.system(size: 14)).foregroundStyle(simulatedText.isEmpty ? p.ink3 : p.ink)
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.field))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.hair, lineWidth: 1))

            if phase != .idle && phase != .done {
                HStack(spacing: 12) {
                    if phase == .listening { Image(systemName: "waveform").foregroundStyle(p.accent) }
                    else if phase == .thinking { ProgressView().controlSize(.small) }
                    else { Image(systemName: "pencil.and.outline").foregroundStyle(p.accent) }
                    Text(capsuleText).font(.system(size: 14)).foregroundStyle(p.ink)
                    Spacer()
                }
                .padding(12).frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.card).shadow(radius: 8, y: 4))
                .padding(.top, 40).padding(.leading, 30)
            }
        }
    }

    // MARK: Real dictation

    private var tapDictationButton: some View {
        let p = appearance.palette
        return Button(action: toggleRealDictation) {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                Text(realDictationButtonTitle).font(.system(size: SkinMetrics.fsBody, weight: .semibold))
            }
        }
        .buttonStyle(.plain).disabled(!canToggleRealDictation).foregroundStyle(p.onAccent)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Capsule().fill(isRecording ? p.accentDeep : p.accent))
        .scaleEffect(isRecording ? 1.04 : 1.0).opacity(canToggleRealDictation ? 1 : 0.7)
        .animation(.easeOut(duration: 0.15), value: isRecording)
        .accessibilityLabel("点按开始说话，再点按把这句话定稿进模拟编辑器")
    }

    private var canToggleRealDictation: Bool { phase == .idle || phase == .listening }

    private var realDictationButtonTitle: String {
        switch phase {
        case .idle: "开始说话"
        case .listening: "结束并定稿"
        case .thinking: "定稿中…"
        case .inserting, .done: "已完成"
        }
    }

    private func toggleRealDictation() {
        switch phase {
        case .idle: beginRealDictation()
        case .listening: endRealDictation()
        case .thinking, .inserting, .done: break
        }
    }

    private func beginRealDictation() {
        guard phase == .idle else { return }
        isRecording = true; phase = .listening; simulatedText = ""; capsuleText = "正在聆听…"
        let locale = UserDefaults.standard.string(forKey: "defaultLocale") ?? CaptureLocale.chinese.rawValue
        do {
            try dictation.start(locale: locale) { partial in
                simulatedText = partial; capsuleText = partial
            }
        } catch {
            isRecording = false; realDictationFailed = true; phase = .idle
        }
    }

    private func endRealDictation() {
        guard phase == .listening else { return }
        isRecording = false; phase = .thinking; capsuleText = "定稿中…"
        Task {
            await dictation.stop()
            if simulatedText.isEmpty { phase = .idle; capsuleText = "" } else { phase = .done }
        }
    }

    private func resetForRetry() {
        isRecording = false; simulatedText = ""; capsuleText = ""; phase = .idle
    }

    // MARK: Scripted fallback (speech denied/unavailable)

    private func simulateInteraction() {
        phase = .listening; capsuleText = "正在聆听..."
        let demo = script
        Task {
            try? await Task.sleep(for: .seconds(1.5)); capsuleText = demo.spoken
            try? await Task.sleep(for: .seconds(1)); phase = .thinking; capsuleText = "正在整理..."
            try? await Task.sleep(for: .seconds(1.2)); phase = .inserting
            let resultText = demo.inserted
            for i in 1...max(resultText.count, 1) {
                simulatedText = String(resultText.prefix(i)); try? await Task.sleep(for: .seconds(0.05))
            }
            try? await Task.sleep(for: .seconds(0.8)); phase = .done
        }
    }
}
