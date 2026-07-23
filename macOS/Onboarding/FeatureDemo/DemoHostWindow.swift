import SwiftUI

/// The mock "host app" each demo plays inside (a tiny title bar + a document / compose body).
/// Renders the selection highlight, phrase-by-phrase transcript, and the in-place replacement
/// purely from `DemoFrameState` — no internal animation or clock.
struct DemoHostWindow: View {
    @Environment(AppearanceStore.self) private var appearance
    let script: FeatureDemoScript
    let state: DemoFrameState

    var body: some View {
        let p = appearance.palette
        VStack(spacing: 0) {
            hostBar(p)
            content(p)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(p.field)
        .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 0.5))
    }

    // MARK: - Chrome

    private func hostBar(_ p: SkinPalette) -> some View {
        HStack {
            Text(script.hostName)
                .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.ink3)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(p.ink3.opacity(0.34)).frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, SkinMetrics.sp3)
        .frame(height: 34)
        .background(p.card2.opacity(0.7))
        .overlay(Rectangle().fill(p.hair).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - Body per host content

    @ViewBuilder private func content(_ p: SkinPalette) -> some View {
        switch script.host {
        case let .document(title, before, selected, after, muted):
            VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
                docTitle(title, p)
                Text(documentParagraph(before: before, selected: selected, after: after, p))
                    .font(.system(size: SkinMetrics.fsBody)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(muted).font(.system(size: SkinMetrics.fsBody)).foregroundStyle(p.ink2)
            }
            .padding(SkinMetrics.sp4)

        case let .dictation(title):
            VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
                docTitle(title, p)
                Text(transcriptParagraph(p)).font(.system(size: SkinMetrics.fsBody)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SkinMetrics.sp4)

        case let .translation(title, source, tail):
            VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
                docTitle(title, p)
                Text(state.contentReplaced ? freshLine(script.target, p) : selectableLine(source, p))
                    .font(.system(size: SkinMetrics.fsBody)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tail).font(.system(size: SkinMetrics.fsBody)).foregroundStyle(p.ink2)
            }
            .padding(SkinMetrics.sp4)

        case let .mail(toLabel, recipient, subjectLabel, subjectText):
            VStack(alignment: .leading, spacing: SkinMetrics.sp2) {
                mailHeader(toLabel, recipient, p)
                mailHeader(subjectLabel, subjectText, p)
                Divider().background(p.hair).padding(.vertical, SkinMetrics.sp1)
                Text(transcriptParagraph(p)).font(.system(size: SkinMetrics.fsBody)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SkinMetrics.sp4)

        case let .webSearchHost(title, query):
            VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
                docTitle(title, p)
                HStack(spacing: SkinMetrics.sp2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(p.ink3)
                    Text(query)
                        .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                        .lineLimit(1)
                }
                .padding(.horizontal, SkinMetrics.sp2).padding(.vertical, SkinMetrics.sp1)
                .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.card2))
                .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.hair, lineWidth: 0.5))

                if state.pillOpacity > 0.5 && state.urlRevealCount == 0 {
                    HStack(spacing: SkinMetrics.sp1) {
                        ProgressView().controlSize(.mini)
                        Text("正在搜索…")
                            .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
                    }
                }
            }
            .padding(SkinMetrics.sp4)

        case let .snap(title, scanLines):
            snapBody(title: title, scanLines: scanLines, p)
        }
    }

    /// 截图识别: a faint "scanned page" with a drag-select marquee growing across the top lines.
    private func snapBody(title: String, scanLines: [String], _ p: SkinPalette) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: SkinMetrics.sp2) {
                docTitle(title, p)
                ForEach(Array(scanLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: SkinMetrics.fsFoot, design: .serif))
                        .foregroundStyle(p.ink3.opacity(0.85))
                }
            }
            .padding(SkinMetrics.sp4)

            if state.marqueeScale > 0.01 {
                let w = DemoTimeline.lerp(70, 320, state.marqueeScale)
                RoundedRectangle(cornerRadius: 3)
                    .fill(p.accent.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(p.accent, lineWidth: 1.5))
                    .frame(width: w, height: 46)
                    .opacity(min(1, state.marqueeScale * 3))
                    .offset(x: SkinMetrics.sp4, y: 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func docTitle(_ t: String, _ p: SkinPalette) -> some View {
        Text(t)
            .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).tracking(1.2)
            .foregroundStyle(p.ink2)
    }

    private func mailHeader(_ label: String, _ value: String, _ p: SkinPalette) -> some View {
        HStack(spacing: SkinMetrics.sp2) {
            Text(label).font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                .frame(width: 46, alignment: .leading)
            Text(value).font(.system(size: SkinMetrics.fsFoot, weight: .semibold)).foregroundStyle(p.ink)
        }
    }

    // MARK: - AttributedString builders

    /// Freshly-inserted text briefly tints accent-green (the "just changed" cue), then settles to ink.
    private func freshColor(_ p: SkinPalette) -> Color {
        state.flashOpacity > 0.15 ? MacPalette.inserted : p.ink
    }

    private func run(_ s: String, _ color: Color) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = color
        return a
    }

    /// Coach: `before` + (selection-highlighted `selected` | freshly-replaced `target`) + `after`.
    private func documentParagraph(before: String, selected: String, after: String, _ p: SkinPalette) -> AttributedString {
        var out = run(before, p.ink)
        if state.contentReplaced {
            out += run(script.target, freshColor(p))
        } else {
            var sel = run(selected, p.ink)
            sel.backgroundColor = p.accent.opacity(0.18 * state.selectScale)
            out += sel
        }
        out += run(after, p.ink)
        return out
    }

    /// Translate: the source line, highlighted as it's "selected" (until the translation lands).
    private func selectableLine(_ source: String, _ p: SkinPalette) -> AttributedString {
        var s = run(source, p.ink)
        if !state.contentReplaced { s.backgroundColor = p.accent.opacity(0.18 * state.selectScale) }
        return s
    }

    private func freshLine(_ text: String, _ p: SkinPalette) -> AttributedString {
        run(text, freshColor(p))
    }

    /// Dictate / English: phrase-by-phrase reveal, then the finalized `target`, plus a caret.
    private func transcriptParagraph(_ p: SkinPalette) -> AttributedString {
        if state.contentReplaced { return freshLine(script.target, p) }
        let shown = Array(script.wordTokens.prefix(state.wordCount))
        var out = AttributedString("")
        for (i, w) in shown.enumerated() {
            out += run(i == 0 ? w : " " + w, p.ink.opacity(0.82))
        }
        out += run(shown.isEmpty ? "▏" : " ▏", p.accent)   // insertion caret
        return out
    }
}
