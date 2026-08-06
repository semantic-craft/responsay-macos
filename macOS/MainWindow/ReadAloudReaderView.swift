import AppKit
import ResponsayCore
import SwiftUI

/// The reader window's contents: the document, and nothing else that isn't a control.
///
/// There is deliberately no progress bar, paragraph rail, or "第 N / M 段" readout. The window
/// *is* the document, so the tinted sentence already says where the read is — a second progress
/// device would restate it. Controls sit in one bottom bar (transport, rate, voice) rather than
/// hiding behind a disclosure: this window is opened occasionally and usually because something
/// needs adjusting.
struct ReadAloudReaderView: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let reader: ReadAloudDocumentReader

    private var palette: SkinPalette { appearanceStore.palette }

    var body: some View {
        VStack(spacing: 0) {
            if reader.hasText {
                document
            } else {
                emptyState
            }
            Divider().overlay(palette.hair)
            ReadAloudReaderControlBar(reader: reader)
        }
        .background(palette.card)
        .background(pasteCatcher)
    }

    // MARK: - Document

    private var document: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(0..<reader.script.paragraphCount, id: \.self) { paragraph in
                        ReadAloudParagraphText(
                            lines: reader.script.lines(inParagraph: paragraph),
                            activeLine: reader.activeLine,
                            progress: reader.lineProgress,
                            palette: palette)
                        .id(paragraph)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 46)
                .padding(.vertical, 30)
            }
            // Follow the read. The viewport can still drift when the user scrolls by hand; the
            // next line change pulls it back, which is the behavior we want for a read-along.
            .onChange(of: reader.activeLine) { _, line in
                guard let line, let entry = reader.script[line] else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(entry.paragraph, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.ink3)
            Text("把要朗读的文字粘进来")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink2)
            Text("⌘V 粘贴，或在别处选中文字后按朗读快捷键送进来。长文也可以，边合成边读。")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("粘贴并朗读") { pasteAndRead() }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// ⌘V anywhere in the window. A zero-size button rather than `onPasteCommand` so the
    /// shortcut works whether or not anything is focused — the window has no text field to
    /// compete with, and an empty reader has nothing focusable at all.
    private var pasteCatcher: some View {
        Button("粘贴并朗读") { pasteAndRead() }
            .keyboardShortcut("v", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func pasteAndRead() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        reader.read(text)
    }
}

/// One paragraph, tinted to show the read position.
///
/// The active line gets a background wash *and* a character sweep. Two devices for one fact
/// because they have different accuracies: the wash is exact (the line's audio duration is
/// measured), while the sweep interpolates within the line and can run slightly ahead or behind.
/// If the sweep drifts, the wash still points at the right sentence.
private struct ReadAloudParagraphText: View {
    let lines: [ReadAloudScript.Line]
    let activeLine: Int?
    let progress: Double
    let palette: SkinPalette

    var body: some View {
        Text(attributed)
            .font(.system(size: 15.5))
            .lineSpacing(7)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for line in lines {
            result.append(render(line))
        }
        return result
    }

    private func render(_ line: ReadAloudScript.Line) -> AttributedString {
        guard let activeLine else { return plain(line.text, color: palette.ink3) }
        if line.id < activeLine { return plain(line.text, color: palette.ink2) }
        if line.id > activeLine { return plain(line.text, color: palette.ink3) }

        let characters = Array(line.text)
        let swept = min(characters.count, Int((Double(characters.count) * progress).rounded()))
        var head = plain(String(characters.prefix(swept)), color: palette.accent)
        head.font = .system(size: 15.5, weight: .semibold)
        let tail = plain(String(characters.dropFirst(swept)), color: palette.ink)
        var whole = head + tail
        whole.backgroundColor = palette.accent.opacity(0.09)
        return whole
    }

    private func plain(_ text: String, color: Color) -> AttributedString {
        var piece = AttributedString(text)
        piece.foregroundColor = color
        return piece
    }
}
