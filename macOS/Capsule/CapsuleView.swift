import SwiftUI
import AppKit
import ResponsayCore

/// The recording indicator hosted in the non-activating panel.
/// `.notch` style is the Dynamic Island (black `NotchShape`, red bars, flush to
/// the hardware notch); `.pill` is the bottom-center native material fallback.
/// Shows `listening` / `thinking` / `error`; empty otherwise.
struct CapsuleView: View {
    var vm: QuickCaptureViewModel
    var notch: Bool

    var body: some View {
        Group {
            if notch { notchBody } else { pillBody }
        }
    }

    // MARK: - Pill (bottom-center, unified Capsule System)
    //
    // The dictation pill and the 任意提问 pill share `UnifiedCapsule` — one warm-paper
    // silhouette, two modes. (The notch variant below stays its own black Dynamic-Island
    // shape, which the warm-paper surface doesn't belong flush against.)
    @ViewBuilder private var pillBody: some View {
        Group {
            if vm.phase == .copied {
                // No editable target → 方案A merge card: 原话摘要 + 复制 (primary) [ + 纠正 ].
                CopyCorrectPillView(
                    vm: vm,
                    copyAction: { copyToPasteboard(); vm.dismissCopied() },
                    correctAction: { vm.beginCorrection() })
            } else {
                UnifiedCapsule(
                    mode: .voice,
                    phase: voicePhase,
                    level: vm.level,
                    thinkingLabel: thinkingLabel,
                    // statusText left empty → the capsule shows its design default ("识别失败 · 请重试").
                    cancelAction: { Task { @MainActor in await vm.cancelCapture() } },
                    finishAction: { Task { @MainActor in await vm.release() } }
                )
                .padding(20)  // room for the shadow inside the panel bounds
            }
        }
        // 复制弹窗: auto-copy on appear so nothing is lost even without a click, then self-dismiss
        // after 5s of no action. `.task(id:)` restarts/cancels with each phase change.
        .task(id: vm.phase) {
            guard vm.phase == .copied else { return }
            copyToPasteboard()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, vm.phase == .copied else { return }
            vm.dismissCopied()
        }
    }

    private func copyToPasteboard() {
        let text = vm.copiedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var voicePhase: CapsulePhase {
        switch vm.phase {
        case .listening:     return .listening
        case .thinking:      return .transcribing
        case .error:         return .error
        case .copied:        return .copied
        case .idle, .review: return .idle
        }
    }

    /// The processing word shown in the thinking pill: 识别中 (snap) / 转写中
    /// (upload+ASR) / 整理中 (polish) / 校验成稿中（实验）(558). One mapping shared
    /// with the notch — see `DictationProgressLabel` (523).
    private var thinkingLabel: String {
        DictationProgressLabel.label(
            finalizing: vm.isFinalizingTranscript, snapRecognizing: vm.snapRecognizing,
            intentCompiling: vm.activeOutputMode == .intentAwareDictation)
    }

    // MARK: - Notch (Dynamic Island)
    private var notchBody: some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(NotchShape().fill(.black))
            .clipShape(NotchShape())
    }

    // MARK: - Content per phase (notch / Dynamic Island only)
    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .listening:
            HStack(spacing: 11) {
                RecordingDot()
                WaveformView(level: vm.level, isRecording: true, style: notch ? .notch : .pill)
                statusText(vm.transcript.isEmpty ? "正在听…" : vm.transcript)
                if let started = vm.recordingStartedAt { TimerLabel(start: started, notch: notch) }
            }
        case .thinking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    statusText(thinkingLabel + "…")
                    if vm.isFinalizingTranscript, !vm.transcript.isEmpty {
                        statusText(vm.transcript, secondary: true)
                    }
                }
            }
        case .error:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(vm.errorMessage ?? "出错了")
                    .font(.callout)
                    .foregroundStyle(notch ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                    .frame(maxWidth: 280, alignment: .leading)
            }
        case .copied:
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(notch ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                statusText(vm.copiedText.isEmpty ? "已复制" : vm.copiedText)
            }
        case .idle, .review:
            EmptyView()
        }
    }

    private func statusText(_ text: String, secondary: Bool = false) -> some View {
        Text(text)
            .font(secondary ? .caption : .callout)
            .lineLimit(1)
            // Truncate the HEAD, not the tail: the live preview must keep the most
            // recently recognized words visible (like macOS/iOS dictation). With the
            // default `.tail`, a growing transcript scrolls its new words off the right
            // edge and the visible head looks frozen ("不会动态跟着字更新"). Harmless for
            // the short status labels ("正在听…") since they never overflow.
            .truncationMode(.head)
            .frame(maxWidth: secondary ? 240 : 280, alignment: .leading)
            .foregroundStyle(statusStyle(secondary: secondary))
    }

    private func statusStyle(secondary: Bool) -> AnyShapeStyle {
        if notch {
            return AnyShapeStyle(.white.opacity(secondary ? 0.68 : 1))
        }
        return AnyShapeStyle(secondary ? .secondary : .primary)
    }
}

// MARK: - Small private helpers

/// A breathing red recording dot (respects Reduce Motion).
struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemRed))
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.0 : 0.7)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

/// A monospaced mm:ss elapsed timer, ticking from the recording start.
private struct TimerLabel: View {
    let start: Date
    var notch: Bool

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()  // report full intrinsic width so the pill grows instead of clipping to "0…"
                .foregroundStyle(notch ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary))
        }
        .accessibilityLabel("录音时长")
    }
}
