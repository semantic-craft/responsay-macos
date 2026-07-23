import SwiftUI
import AppKit
import ResponsayCore

/// The Intent-aware Dictate **safe-unavailable** card (#559): the compiler / plan / guard could not
/// prove the result safe, so nothing was inserted. It names the category (无 Key / 能力不支持 /
/// 不可达 / 超时 / 坏响应 / verifier 拒) in content-free copy, shows the user's own words for
/// copy only — never a one-click reinsert of the raw transcript (spec decision 23) — and offers
/// 重试 (only when a fresh attempt could help) and the independent 转普通听写. Fully keyboard /
/// VoiceOver operable; the "未上屏" status carries an icon so it does not depend on colour.
struct IntentSafeUnavailableCardView: View {
    var vm: QuickCaptureViewModel
    let reason: IntentUnavailableReason

    @State private var isCopied = false
    @FocusState private var copyFocused: Bool
    // 566: the active compile route (云端 / 本机 / 未配置), so an unavailable result also shows
    // whether the attempt went local or to the cloud and which provider (spec #59). Resolved once
    // when the card appears — content-free (provider id only).
    @State private var route: IntentCompilerRoute = .unavailable

    private var copy: (title: String, body: String, isRetryable: Bool) { IntentReviewReasonCopy.present(reason) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("校验成稿（实验）")
                    .font(.system(size: 11, weight: .semibold)).textCase(.uppercase).kerning(0.4)
                    .foregroundStyle(CapsuleSystemTheme.accentText)
                Label("未上屏", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CapsuleSystemTheme.err)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("校验成稿实验，状态：未上屏")

            Text(copy.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CapsuleSystemTheme.ink)
            Text(copy.body)
                .font(.system(size: 12))
                .foregroundStyle(CapsuleSystemTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            Label(route.displayLabel, systemImage: route.isLocal ? "desktopcomputer" : "cloud")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CapsuleSystemTheme.ink2)
                .accessibilityLabel("成稿路线：\(route.displayLabel)")

            if !vm.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("你的原话（仅供复制，不会一键写入）")
                        .font(.caption).foregroundStyle(CapsuleSystemTheme.ink2)
                    Text(vm.transcript)
                        .font(.system(size: 13))
                        .foregroundStyle(CapsuleSystemTheme.ink)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CapsuleSystemTheme.chip))
                        .accessibilityLabel("你的原话：\(vm.transcript)")
                }
            }

            HStack(spacing: 10) {
                if !vm.transcript.isEmpty {
                    Button(action: copyOwnWords) {
                        Label(isCopied ? "已复制" : "复制原话", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(CapsuleSystemTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("c", modifiers: .command)
                    .focused($copyFocused)
                    .accessibilityLabel(isCopied ? "已复制原话" : "复制原话到剪贴板")
                }
                if copy.isRetryable {
                    Button { Task { await vm.retryIntentCompilation() } } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(CapsuleSystemTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("重试校验成稿")
                }
                Spacer(minLength: 0)
                Button("取消") { vm.discard() }
                    .buttonStyle(.plain)
                    .foregroundStyle(CapsuleSystemTheme.ink2)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("取消并丢弃本次结果")
            }

            IntentConvertConfirmSection(vm: vm)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(16)
        .onExitCommand { vm.discard() }
        .onAppear {
            copyFocused = true
            route = IntentCompilerRoute.classify(LLMEndpointResolver.resolveText())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("校验成稿实验：本次未上屏，\(copy.title)。原话未写入。")
    }

    private func copyOwnWords() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(vm.transcript, forType: .string)
        guard !isCopied else { return }
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
    }
}
