import SwiftUI
import AppKit
import ResponsayCore

/// The Intent-aware Dictate **needs-review** card (#559). It surfaces only the minimal, sanitized
/// review data — a draft the user may edit and grounded candidates with short evidence labels —
/// never the provider response, the raw side notes, the screen context, or the internal plan.
/// Every path that can reach the target field re-runs the verifier + guard (confirm a candidate,
/// re-verify an edit); there is deliberately NO one-click "insert raw / continue as-is". The
/// escape hatches — retry and 转普通听写 — are independent, visibly-routed decisions.
///
/// Fully keyboard-operable on the keyable `ReviewPanel`: Tab moves between candidates / editor /
/// actions, Return re-verifies the edit, ⌘C copies the safe draft, ⌘R retries, Esc cancels.
struct IntentReviewCardView: View {
    var vm: QuickCaptureViewModel

    @State private var draftText = ""
    @State private var didSeedDraft = false
    @State private var isCopied = false
    @FocusState private var focus: Field?
    private enum Field: Hashable { case draft, candidate(String), copy }

    private var content: IntentReviewContent { vm.intentReviewContent ?? IntentReviewContent(sanitizedDraft: nil, candidates: []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(reasonLine)
                .font(.system(size: 12))
                .foregroundStyle(CapsuleSystemTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if content.sanitizedDraft != nil { draftEditor }
            if !content.candidates.isEmpty { candidateList }
            if !content.isResolvable { ownWords }        // generic review: show your own words to copy
            if vm.intentReviewReverifyRejected { rejectedNotice }

            actions
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
        .onAppear(perform: seedAndFocus)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("校验成稿实验：需要你确认后才会上屏。原话未写入。")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Text("校验成稿（实验）")
                .font(.system(size: 11, weight: .semibold)).textCase(.uppercase).kerning(0.4)
                .foregroundStyle(CapsuleSystemTheme.accentText)
            // Non-colour status: an icon + words, so the state reads without relying on hue.
            Label("需确认", systemImage: "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CapsuleSystemTheme.ink2)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("校验成稿实验，状态：需要你确认")
    }

    private var draftEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("草稿（可编辑，改后需重验）")
                .font(.caption).foregroundStyle(CapsuleSystemTheme.ink2)
            TextField("草稿", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(CapsuleSystemTheme.ink)
                .lineLimit(1...6)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(CapsuleSystemTheme.chip))
                .focused($focus, equals: .draft)
                .onSubmit(submitEdit)
                .accessibilityLabel("可编辑草稿")
            Button(action: submitEdit) {
                Label("重验并写入", systemImage: "checkmark.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.accent))
                    .foregroundStyle(CapsuleSystemTheme.accentInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新校验草稿并写入")
            .accessibilityHint("编辑后的草稿会再过一次安全校验，通过才写入")
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选一个后重验写入")
                .font(.caption).foregroundStyle(CapsuleSystemTheme.ink2)
            ForEach(content.candidates) { candidate in
                Button {
                    Task { await vm.confirmIntentCandidate(id: candidate.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(CapsuleSystemTheme.accentText)
                        Text(candidate.value)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CapsuleSystemTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(candidate.evidence)
                            .font(.caption2)
                            .foregroundStyle(CapsuleSystemTheme.ink2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.chip))
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(CapsuleSystemTheme.chip.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .candidate(candidate.id))
                .accessibilityLabel("确认候选：\(candidate.value)，依据 \(candidate.evidence)")
                .accessibilityHint("确认后会重新经过校验再写入")
            }
        }
    }

    private var ownWords: some View {
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

    private var rejectedNotice: some View {
        Label("刚才的内容没通过安全校验，请调整后再试——仍未写入。", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(CapsuleSystemTheme.err)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("提示：刚才的确认或编辑没通过安全校验，仍停留在确认界面，未写入")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: copySafeDraft) {
                    Label(isCopied ? "已复制" : "复制安全草稿", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(CapsuleSystemTheme.ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
                .focused($focus, equals: .copy)
                .accessibilityLabel(isCopied ? "已复制安全草稿" : "复制当前安全草稿")

                Button { Task { await vm.retryIntentCompilation() } } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(CapsuleSystemTheme.ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("重试校验成稿")

                Spacer(minLength: 0)

                Button("取消") { vm.discard() }
                    .buttonStyle(.plain)
                    .foregroundStyle(CapsuleSystemTheme.ink2)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("取消并丢弃本次结果")
            }
            IntentConvertConfirmSection(vm: vm)
        }
    }

    // MARK: - Copy / behaviour

    private var reasonLine: String {
        // Content-free category copy only (#559/#561): the reason names WHY review is needed,
        // never echoing the transcript, the cue span, or the internal plan.
        if case let .needsReview(reason) = vm.intentCaptureState {
            switch reason {
            case .unexplainedCorrectionCue:
                return "原话里像是有明显的改口，但这次的结果没有解释清楚它。可编辑草稿或复制原话处理——未确认不会写入。"
            case .unexplainedSideNoteCue:
                return "原话里像是有只说给法言听的旁注，这次的结果没有把它分开。为避免旁注泄漏，需要你确认后才写入。"
            case .unexplainedGroundingCue:
                return "原话里像是有逐字释义的提示，这次的结果没有把它当作线索处理。请确认后再写入，避免提示词进入正文。"
            case .ambiguousEntityCandidates:
                return "同一个名字或术语有多个可信写法。选一个候选后会重新校验再写入。"
            case .compilerRequested:
                break
            }
        }
        return content.isResolvable
            ? "模型对这句里的改口或指向不够确定。确认候选、或编辑草稿后重验才会写入。"
            : "这句需要你确认后才会写入。可复制原话手动处理，或转普通听写。"
    }

    private func seedAndFocus() {
        if !didSeedDraft {
            draftText = content.sanitizedDraft ?? ""
            didSeedDraft = true
        }
        // Default focus on the safest primary action: the editor if there's a draft, else the
        // first candidate, else the copy button.
        if content.sanitizedDraft != nil {
            focus = .draft
        } else if let first = content.candidates.first {
            focus = .candidate(first.id)
        } else {
            focus = .copy
        }
    }

    private func submitEdit() {
        Task { await vm.submitIntentEditedDraft(draftText) }
    }

    private func copySafeDraft() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(vm.intentSafeCopyText, forType: .string)
        guard !isCopied else { return }   // one success feedback per operation
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
    }
}
