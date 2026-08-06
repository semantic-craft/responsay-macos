import ResponsayCore
import SwiftUI

/// The reader's one control bar: transport, rate, voice.
///
/// Rate is a continuous slider over 0.5–2.0× — the window Qwen's realtime `rate` actually
/// accepts, and the range every other provider is clamped to. Releasing it restarts at the head
/// of the sentence being spoken, because audio already queued was synthesized at the old rate;
/// that is why the caption says 从本句生效 instead of pretending the change is instantaneous.
struct ReadAloudReaderControlBar: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let reader: ReadAloudDocumentReader

    @State private var draftSpeed: Double = 1.0
    @State private var engine: TTSEngine = .selected
    @State private var voiceID: String? = TTSEngine.selected.selectedVoiceID

    private var palette: SkinPalette { appearanceStore.palette }
    private var voices: [TTSVoiceSpec] { engine.catalog?.voices ?? [] }

    var body: some View {
        HStack(spacing: 13) {
            transport
            rate
            Spacer(minLength: 8)
            voicePicker
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.card2)
        .overlay(alignment: .top) { notice }
        .onAppear {
            draftSpeed = reader.speed
            engine = .selected
            voiceID = engine.selectedVoiceID
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 8) {
            Button { reader.pauseOrResume() } label: {
                Image(systemName: reader.phase == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(!reader.hasText || reader.phase == .preparing)
            .opacity(!reader.hasText || reader.phase == .preparing ? 0.45 : 1)
            .accessibilityLabel(reader.phase == .playing ? "暂停朗读" : "继续朗读")

            Button { reader.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.ink2)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(palette.hairStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!reader.isActive)
            .opacity(reader.isActive ? 1 : 0.45)
            .accessibilityLabel("停止朗读")
        }
    }

    // MARK: - Rate

    private var rate: some View {
        HStack(spacing: 8) {
            Text("语速").font(.system(size: 10)).tracking(1.2)
                .foregroundStyle(palette.ink3)
            Slider(
                value: $draftSpeed,
                in: ReadAloudDocumentReader.speedRange,
                onEditingChanged: { editing in
                    // Commit on release only: dragging would otherwise restart synthesis on
                    // every intermediate value.
                    if !editing { reader.setSpeed(draftSpeed) }
                })
            .controlSize(.small)
            .frame(width: 116)
            .accessibilityLabel("朗读语速")
            Text(String(format: "%.2f×", draftSpeed))
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.ink3)
                .frame(width: 42, alignment: .leading)
        }
        .help("0.5×–2.0×，松手后从本句开始生效")
    }

    // MARK: - Voice

    @ViewBuilder
    private var voicePicker: some View {
        HStack(spacing: 7) {
            Text("音色").font(.system(size: 10)).tracking(1.2)
                .foregroundStyle(palette.ink3)
            if voices.isEmpty {
                // On-device Kokoro ships one voice, so there is nothing to choose between.
                Text(engine.title)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink2)
            } else {
                Picker("音色", selection: voiceBinding) {
                    ForEach(voices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .help("切换后从本句开始用新音色")
            }
        }
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { voiceID ?? engine.catalog?.defaults.voiceID ?? "" },
            set: { picked in
                guard picked != voiceID else { return }
                voiceID = picked
                engine.setSelectedVoiceID(picked)
                // Restarting the current line is itself the audition — no separate 试听 button.
                reader.voiceDidChange()
            })
    }

    // MARK: - Notice

    @ViewBuilder
    private var notice: some View {
        if let message = reader.errorMessage ?? reader.voiceNotice {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(reader.errorMessage == nil ? palette.ink3 : Color.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.card2)
                .offset(y: -20)
        }
    }
}
