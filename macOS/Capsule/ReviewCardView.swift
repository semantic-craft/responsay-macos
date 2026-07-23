import SwiftUI
import AppKit
import ResponsayCore

/// The interactive review card: idiomatic English (big) + why, with
/// Enter to insert, Esc to discard, and ⌘C to copy.
/// Hosted in the keyable `ReviewPanel`.
struct ReviewCardView: View {
    var vm: QuickCaptureViewModel
    
    @AppStorage("reviewCardIsPinned") private var isPinned: Bool = false
    @State private var isCopied: Bool = false
    @State private var globalMonitor: Any?
    // 395 — 🔊 朗读地道外文. Card-scoped read-aloud engine; reuses the shared TTS path
    // (selected engine → Kokoro → Apple fallback) via a plain-text seed.
    @State private var reader = ReadAloudController()

    private var readAloudText: String {
        Self.readAloudText(result: vm.result, activeIdiomatic: vm.activeIdiomatic)
    }

    nonisolated static func readAloudText(result: ExpressionResult?, activeIdiomatic: String) -> String {
        guard result != nil else { return "" }
        return activeIdiomatic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // Which card is derived once by CaptureReviewState (#3), not inferred from an optional
        // cascade — and `.empty` renders nothing instead of a silently-blank coach card.
        switch vm.reviewState {
        case .legalConfirm(let confirm):
            // 110: send-preview gate before a cloud legal call.
            LegalSendPreviewView(
                decision: confirm,
                onConfirm: { Task { await vm.confirmLegalSend() } },
                onCancel: { vm.cancelLegalSend() })
        case .legalResult(let response, _):
            // 107: a run skill's structured output takes over the panel (wide; gated insert).
            LegalSkillOutputView(
                response: response,
                searchPermission: vm.legalSearchPermission,
                onSearchVerify: { anchor in try await vm.verifyLegalAnchor(anchor) },
                onAnchorConfirmed: { anchor, source in vm.confirmLegalAnchor(anchor, source: source) },
                onInsert: { aff in Task { await vm.insertLegalText(aff.text, skipsTagging: aff.kind == .query) } },
                onDismiss: { vm.discard() },
                onDebate: vm.legalResultDebateScript == nil ? nil : { vm.continueLegalResultAsDebate() },
                caseCandidates: vm.legalCaseCandidates,
                isFindingCases: vm.isFindingCases,
                onFindSimilarCases: {   // 488 找类案：default-off, user-triggered
                    Task { await vm.findSimilarCases(
                        query: vm.transcript,
                        currentYear: Calendar.current.component(.year, from: Date())) }
                })
        case .coach:
            coachReview
        case .intentNeedsReview:
            // 559 — the full keyboard-first review card: sanitized draft (editable, re-verified),
            // grounded candidates (confirm re-runs verifier+guard), copy safe draft, retry, and the
            // independent 转普通听写. No one-click raw insert.
            IntentReviewCardView(vm: vm)
        case .intentSafeUnavailable:
            // 559 — the safe-unavailable card names the category (无 Key / 不可达 / 坏响应 / …) and
            // offers copy-your-words + retry + convert, never a trusted raw write-back.
            if case let .safeUnavailable(reason) = vm.intentCaptureState {
                IntentSafeUnavailableCardView(vm: vm, reason: reason)
            }
        case .empty:
            EmptyView()
        }
    }

    private var coachReview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("✓ 地道说法")
                    .font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                    .kerning(0.4).foregroundStyle(MacPalette.accent)
                
                Spacer()
                
                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(isPinned ? MacPalette.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消钉住" : "钉住屏幕")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 11) {

            // 你说的 — original with red strikethrough (English source only)
            if let result = vm.result, case let .diff(segs) = CoachDiffPresentation.make(
                original: result.original, idiomatic: result.idiomatic) {
                Text("你说的：").foregroundStyle(.secondary).font(.system(.caption, design: .monospaced))
                DiffSegmentsText(segments: segs, projection: .original)
                    .font(.system(.caption, design: .default)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !vm.transcript.isEmpty {
                Text(vm.transcript).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2)
            }

            // teal→green gradient hairline
            LinearGradient(colors: [MacPalette.prosody.opacity(0.7), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            // idiomatic headline (green inserted words when showing the main idiomatic)
            headline

            // reasons with green ticks
            if let result = vm.result, !result.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(result.reasons, id: \.self) { reason in
                        Label {
                            Text(reason).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark").font(.caption2.weight(.bold))
                                .foregroundStyle(MacPalette.accent)
                        }
                    }
                }
            }

            // 422 — 我怎么理解你的 (intentNote): only present when 猜测意图 reconstructed a
            // tangled utterance (原 X → 我理解为 Y). Faithful leaves it empty → not shown.
            if let note = vm.result?.intentNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我怎么理解你的").font(.caption.weight(.semibold)).foregroundStyle(MacPalette.accent)
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 11).padding(.vertical, 9).padding(.trailing, 11)
                .background(MacPalette.accent.opacity(0.08))
                .overlay(alignment: .leading) { Rectangle().fill(MacPalette.accent).frame(width: 2) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // 中式 → 美式 (thinkingShift) — green-tint left-border block
            if let shift = vm.result?.thinkingShift, !shift.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("中式 → 美式").font(.caption.weight(.semibold)).foregroundStyle(MacPalette.prosody)
                    Text(shift).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 11).padding(.vertical, 9).padding(.trailing, 11)
                .background(MacPalette.prosody.opacity(0.08))
                .overlay(alignment: .leading) { Rectangle().fill(MacPalette.prosody).frame(width: 2) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // 298: legal follow-up ask — explain the [待核] tags the discipline just
            // injected. Only shown when the answer actually carries a tag (no false
            // claims when the answer had no coordinates).
            if vm.askSession?.mode == .legal, vm.activeIdiomatic.contains("[待核]") {
                Label("法律追问：回答中新出现的法条/案号已标 [待核]，插入时保留",
                      systemImage: "checkmark.shield")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // 别的说法 — tappable chips that swap the active sentence
            if let alts = vm.result?.alternatives, !alts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("别的说法").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(alts, id: \.self) { alt in
                        Button { vm.selectAlternative(alt) } label: {
                            Text(alt).font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6).padding(.horizontal, 10)
                                .background((vm.activeIdiomatic == alt ? MacPalette.prosody.opacity(0.16)
                                                                      : Color.primary.opacity(0.05)))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("用备选说法：\(alt)")
                    }
                }
            }
                }
                .padding(.trailing, 4)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 400)

            actionRow   // 插入 / 丢弃 / 复制 — insert uses activeIdiomatic, tint MacPalette.accent
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: SkinMetrics.radiusCard, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: SkinMetrics.radiusCard, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
        .padding(24)  // room for the shadow inside the panel bounds
        .onAppear { setupGlobalMonitor(); reader.cachesComposedAudio = true }   // 495: Coach lines are cacheable
        .onDisappear { teardownGlobalMonitor(); reader.stop() }
        // 395 — switching to another 别的说法 changes the active sentence → stop, so the
        // 🔊 button never keeps reading a sentence that's no longer on screen.
        .onChange(of: vm.activeIdiomatic) { reader.stop() }
    }

    @ViewBuilder private var headline: some View {
        if let result = vm.result {
            let isMain = vm.activeIdiomatic == result.idiomatic
            if isMain, case let .diff(segs) = CoachDiffPresentation.make(
                original: result.original, idiomatic: result.idiomatic) {
                DiffSegmentsText(segments: segs, projection: .idiomatic)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else {
                Text(vm.activeIdiomatic)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundStyle(.primary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            if vm.didAutoInsertResult {
                Label("已上屏", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MacPalette.accent)

                Button("关闭") { vm.discard() }
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button { reader.stop(); Task { await vm.confirmInsert() } } label: {
                    Label("写入", systemImage: "return")
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(MacPalette.accent)
                .foregroundStyle(MacPalette.accentInk)

                Button("丢弃") { vm.discard() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Button { copyIdiomatic() } label: {
                Label(isCopied ? "已复制" : "复制", systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)

            if !readAloudText.isEmpty { readAloudButton }

            if let message = reader.lastErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let notice = reader.activeVoiceNotice {   // 497: fallback voice in use
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // 继续追问 — only in the selection-ask flow; re-enters listening on the
            // same session so the next question carries this answer (real multi-turn).
            if let session = vm.askSession, !session.reachedTurnLimit {
                Button { reader.stop(); vm.prepareFollowUpAndListen() } label: {
                    Label("继续追问", systemImage: "arrow.turn.down.right")
                }
                .accessibilityLabel("继续追问选中内容")
                .help("基于这段对话再问一句")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// 395 — 🔊 朗读当前激活的地道外文 (`readAloudText`). Play/stop toggle: tap to read,
    /// tap again to stop (full stop, not pause — re-tap reads from the start). Reuses the
    /// shared read-aloud engine via the plain-text seed (same path as 朗读选中文本); audio
    /// only, no word highlight. The engine falls back Kokoro→Apple so it speaks with zero
    /// TTS setup; synth/playback failures show a short inline error.
    private var readAloudButton: some View {
        Button {
            if reader.isPlaying {
                reader.stop()
            } else {
                reader.toggleRead(.followReadSeed(from: readAloudText))
            }
        } label: {
            Label(reader.isPlaying ? "停止" : (reader.isPreparing ? "准备中" : "朗读"),
                  systemImage: reader.isPlaying ? "stop.fill" : "speaker.wave.2")
        }
        .disabled(reader.isPreparing && !reader.isPlaying)
        .accessibilityLabel(reader.isPlaying ? "停止朗读" : "朗读地道外文")
    }

    private func copyIdiomatic() {
        guard let result = vm.result else { return }
        NSPasteboard.general.clearContents()
        
        var fullText = "你说的：\n\(result.original)\n\n地道说法：\n\(vm.activeIdiomatic)"
        
        if !result.reasons.isEmpty {
            fullText += "\n\n修改原因：\n" + result.reasons.map { "• \($0)" }.joined(separator: "\n")
        }
        
        let shift = result.thinkingShift
        if !shift.isEmpty {
            fullText += "\n\n中式 → 美式：\n\(shift)"
        }
        
        let otherAlts = result.alternatives.filter { $0 != vm.activeIdiomatic }
        if !otherAlts.isEmpty {
            fullText += "\n\n别的说法：\n" + otherAlts.map { "• \($0)" }.joined(separator: "\n")
        }
        
        NSPasteboard.general.setString(fullText, forType: .string)
        
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
    
    private func setupGlobalMonitor() {
        if globalMonitor != nil { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if !isPinned {
                // Ignore clicks if the app is active, otherwise global monitor catches clicks outside the app
                vm.discard()
            }
        }
    }
    
    private func teardownGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
