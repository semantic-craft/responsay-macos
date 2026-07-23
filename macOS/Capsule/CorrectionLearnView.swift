import SwiftUI
import ResponsayCore

/// 518: the correction mini panel — shows the just-inserted text, lets the user pick (or type)
/// the misheard word plus the correct spelling, and confirms into
/// `CaptureCorrectionLearner.learn` (dictionary + learned alias in one action).
///
/// Pure SwiftUI on the keyable `ReviewPanel` host; every button is `.plain` (1.3.22 iron rule).
struct CorrectionLearnView: View {
    var vm: QuickCaptureViewModel
    /// Injectable for previews/tests; production default writes the real defaults + toast.
    var learn: (String, String) -> CaptureCorrectionLearner.Outcome = {
        CaptureCorrectionLearner.learn(wrong: $0, correct: $1)
    }

    @State private var wrongText = ""
    @State private var correctText = ""
    @State private var rejection: String?
    @FocusState private var focusedField: Field?
    private enum Field { case wrong, correct }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("纠正听写 · 学到词典")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CapsuleSystemTheme.ink)
            Text("点选听错的词（或手动输入），再填正确写法。确认后 app 会偏向正确拼写，同样的错法下次自动修正。")
                .font(.caption)
                .foregroundStyle(CapsuleSystemTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let draft = vm.correctionDraft {
                Text(draft)
                    .font(.callout)
                    .foregroundStyle(CapsuleSystemTheme.ink2)
                    .lineLimit(3)
                    .truncationMode(.middle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.pickableWords(in: draft), id: \.self) { word in
                            Button(word) {
                                wrongText = word
                                focusedField = .correct
                            }
                            .buttonStyle(.plain)   // 1.3.22 iron rule
                            .font(.callout)
                            .foregroundStyle(CapsuleSystemTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.chip))
                            .accessibilityLabel("选择错词 \(word)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            TextField("听错的词", text: $wrongText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .wrong)
            TextField("正确写法", text: $correctText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .correct)
                .onSubmit(confirm)

            if let rejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(CapsuleSystemTheme.err)
            }

            HStack {
                Spacer()
                Button("取消") { vm.dismissCorrection() }
                    .buttonStyle(.plain)   // 1.3.22 iron rule
                    .foregroundStyle(CapsuleSystemTheme.ink2)
                Button(action: confirm) {
                    Text("确认并学习")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(CapsuleSystemTheme.accent))
                        .foregroundStyle(CapsuleSystemTheme.accentInk)
                }
                .buttonStyle(.plain)   // 1.3.22 iron rule
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CapsuleSystemTheme.surface))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CapsuleSystemTheme.line, lineWidth: 1.5))
        .shadow(color: CapsuleSystemTheme.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(16)  // shadow/keyline breathing room inside the panel bounds
        .onExitCommand { vm.dismissCorrection() }   // Esc closes (panel is key)
    }

    private func confirm() {
        switch learn(wrongText, correctText) {
        case .learned:
            vm.dismissCorrection()
        case let .rejected(reason):
            rejection = reason
        }
    }

    /// Tappable word chips from the inserted text: whitespace/punctuation-separated chunks,
    /// deduped in order, capped so a long paragraph can't flood the row.
    static func pickableWords(in text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 && seen.insert($0).inserted }
            .prefix(10)
            .map { String($0.prefix(20)) }
    }
}
