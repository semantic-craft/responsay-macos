import SwiftUI
import AppKit
import ResponsayCore

/// 任意提问 answer card — Capsule System "Answer popup". A **voice-native** warm-paper card
/// (460 × 548, never black/blue), deliberately *not* a chat clone:
/// - left-aligned ✦ Responsay wordmark + a "· 任意提问" mode tag, ✕ to close,
/// - each spoken question reads as a **voice-origin chip** (mini waveform + the question),
/// - each answer carries a meta line (✦ 回答 · reading time) so you can read or listen,
/// - a voice-forward action bar: 🔊 朗读 · 复制 · 重新生成 · ⌥ 追问 (the Option trigger).
///
/// Colours come from `SettingsTheme` (→ `Skin.current.palette`), so switching skin re-tints
/// the card. Rendered in a FIXED-size panel (`VoiceAssistantPanel.showResult`): the body
/// scrolls, the window never resizes mid-stream. Keep the frame fixed.
@MainActor
struct VoiceAssistantResultPanel: View {
    var vm: VoiceAssistantViewModel
    /// Dismiss the card. The owning `VoiceAssistantPanel` actually orders the window out —
    /// clearing the conversation alone can't hide it, because the panel's show/hide observer
    /// tracks only `phase` / `selectionContext`, not `messages` (see VoiceAssistantPanel.observe).
    var onClose: () -> Void = {}
    @State private var reader = ReadAloudController()

    private var chip: Color { SettingsTheme.ink.opacity(0.07) }

    /// The latest assistant answer — what 朗读 / 复制 / 重新生成 act on.
    private var latestAnswer: String {
        for message in vm.messages.reversed() where message.role == "assistant" {
            return message.content
        }
        return ""
    }

    private var latestReadAloudText: String {
        Self.readAloudText(from: vm.messages)
    }

    nonisolated static func readAloudText(from messages: [VoiceAssistantMessage]) -> String {
        for message in messages.reversed() where message.role == "assistant" {
            return plainTextForReadAloud(message.content)
        }
        return ""
    }

    nonisolated static func plainTextForReadAloud(_ s: String) -> String {
        var out = s
        for token in ["**", "`", "#", "> ", "- ", "* "] {
            out = out.replacingOccurrences(of: token, with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let selection = vm.selectionContext {
                            SelectionSourceChip(text: selection, chip: chip)
                        }
                        if vm.messages.isEmpty {
                            emptyHint
                        }
                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, message in
                            if message.role == "user" {
                                QuestionChip(text: message.content).id(message.id)
                            } else {
                                AnswerSection(text: message.content, showCaret: isStreamingTail(index))
                                    .id(message.id)
                            }
                        }
                        if let error = vm.errorMessage {
                            errorRow(error)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.messages.last?.content) {
                    guard let last = vm.messages.last?.id else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }

            actionBar
        }
        .frame(width: 460, height: 548)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SettingsTheme.card))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        // Warm paper drop shadow (design: 0 32px 72px -26px rgba(0,0,0,.55)).
        .shadow(color: .black.opacity(0.42), radius: 32, y: 18)
        .padding(24)  // room for the shadow inside the panel bounds
        .onChange(of: latestReadAloudText) { reader.stop() }
        .onDisappear { reader.stop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Text("✦").font(.system(size: 13)).foregroundStyle(SettingsTheme.wine)
            Text(AppBrand.displayName)
                .font(SkinMetrics.serif(15.5, weight: .bold))
                .foregroundStyle(SettingsTheme.ink)
            Text("· 任意提问")
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.ink3)
            if let id = vm.searchProviderId,
               let src = VoiceAssistantSearchModelSettings.capsuleSource(for: id) {
                Text("· 联网搜索 · \(src.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.wine)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HoverIconButton(systemName: "xmark", chip: chip) {
                reader.stop()
                onClose()
            }
            .accessibilityLabel("关闭")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    // MARK: - Action bar (voice-forward)

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(SettingsTheme.hair)
            HStack(spacing: 8) {
                ReadAloudButton(
                    isPlaying: reader.isPlaying,
                    isPreparing: reader.isPreparing,
                    enabled: reader.isPlaying || (!reader.isPreparing && vm.phase != .responding && !latestReadAloudText.isEmpty)
                ) {
                    reader.toggleRead(.followReadSeed(from: latestReadAloudText))
                }
                IconActionButton(systemName: "doc.on.doc", flashSystemName: "checkmark",
                                 enabled: !latestAnswer.isEmpty, accessibility: "复制回答") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(latestAnswer, forType: .string)
                    return true
                }
                IconActionButton(systemName: "arrow.clockwise", flashSystemName: nil,
                                 enabled: !latestAnswer.isEmpty && vm.phase != .responding,
                                 accessibility: "重新生成") {
                    reader.stop()
                    Task { await vm.regenerate() }
                    return false
                }
                Spacer(minLength: 0)
                AskMoreHint()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if let message = reader.lastErrorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsTheme.amber)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let notice = reader.activeVoiceNotice {   // 497: fallback voice in use
                Text(notice)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Inline rows

    private var emptyHint: some View {
        // Neutral prompt — no trigger-method text (点按/按住/键名). Like Typeless, we don't
        // surface "how to trigger" here; the gesture is the user's own setting.
        Label(
            vm.selectionContext != nil ? "对这段选区提问" : "开始提问",
            systemImage: "mic.circle"
        )
        .font(.system(size: 13))
        .foregroundStyle(SettingsTheme.ink3)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 34)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SettingsTheme.amber)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(SettingsTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func isStreamingTail(_ index: Int) -> Bool {
        vm.phase == .responding && index == vm.messages.count - 1
    }
}

// MARK: - Voice-origin question chip (mini waveform + spoken question)

@MainActor
private struct QuestionChip: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MiniWaveform()
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(SettingsTheme.wine.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsTheme.wine.opacity(0.12), lineWidth: 1))
    }
}

/// Five static wine bars — a "this came from your voice" cue (decorative).
@MainActor
private struct MiniWaveform: View {
    private let heights: [CGFloat] = [5, 11, 8, 13, 6]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 1)
                    .fill(SettingsTheme.wine)
                    .frame(width: 2, height: h)
            }
        }
        .frame(height: 13)
        .accessibilityHidden(true)
    }
}

// MARK: - Answer section (✦ 回答 · reading time + Markdown)

@MainActor
private struct AnswerSection: View {
    let text: String
    let showCaret: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("✦ 回答")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.wine)
                if !text.isEmpty {
                    Text("· \(readingTime(text))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsTheme.ink3)
                }
                Spacer(minLength: 0)
            }
            if text.isEmpty {
                Text("思考中…")
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.ink3)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    AnswerMarkdownView(text: text)
                    if showCaret { BlinkingCaret() }
                }
            }
        }
    }

    /// Rough "约 N 秒/分钟读完" from character count (~5 chars/sec).
    private func readingTime(_ text: String) -> String {
        let seconds = max(1, Int((Double(text.count) / 5.0).rounded()))
        if seconds < 60 { return "约 \(seconds) 秒读完" }
        return "约 \(Int((Double(seconds) / 60).rounded())) 分钟读完"
    }
}

// MARK: - Selection-source chip (✂︎ 选区来源)

@MainActor
private struct SelectionSourceChip: View {
    let text: String
    let chip: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("✂︎").font(.system(size: 11))
            Text(text)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(SettingsTheme.ink2)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(chip))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsTheme.hair, lineWidth: 1))
    }
}

// MARK: - Small shared controls

/// A rounded hover icon button (header close ✕).
@MainActor
private struct HoverIconButton: View {
    let systemName: String
    let chip: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? chip : .clear))
                .foregroundStyle(hovering ? SettingsTheme.ink : SettingsTheme.ink3)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Blinking wine caret shown at the tail of a streaming answer.
@MainActor
private struct BlinkingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(SettingsTheme.wine)
            .frame(width: 7, height: 15)
            .opacity(on ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: on)
            .onAppear { if !reduceMotion { on = false } }
            .accessibilityHidden(true)
    }
}
