import SwiftUI
import AppKit
import ResponsayCore

/// 截图取字 结果卡片（暖纸）。三件事，对齐 Bob 取字窗口：
/// 1. **复制文本** — 取字结果可编辑、一键复制（且打开即自动写入剪贴板，保留旧「截图复制」的零点击习惯）；
    /// 2. **智能分段** — 智能分段 ↔ 原始分行切换（按 OCR 输出形态选择几何或逐行策略）；
/// 3. **切换引擎再识别** — 顶部引擎下拉换 OCR 服务商，就地对同一张截图重新识别（无需重新框选）。
///
/// 配色走 `SettingsTheme`（→ 当前皮肤），与任意提问回答卡同语言。读钥匙串只在「切换引擎」这一显式动作里
/// 发生（`reOCR()` 内），绝不进 `body`——见 keychain-on-render 冻结教训。
@MainActor
struct SnapOCRPanelView: View {
    let sourceImage: NSImage
    let cgImage: CGImage
    var onClose: () -> Void

    @Environment(\.undoManager) private var undoManager
    @AppStorage(OCREngine.defaultsKey) private var engineRaw = OCREngine.appleVision.rawValue
    @State private var draft: OCRTextDraft
    @State private var showSource = false
    @State private var isReOCRing = false
    @State private var fellBackToLocal = false
    @State private var didAutoCopy = false

    private var engine: OCREngine { OCREngine(rawValue: engineRaw) ?? .appleVision }
    private var supportsSmartParagraphing: Bool { draft.supportsSmartParagraphing }
    private var chip: Color { SettingsTheme.ink.opacity(0.07) }

    init(result: OCRResult, sourceImage: NSImage, cgImage: CGImage, onClose: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self.cgImage = cgImage
        self.onClose = onClose
        _draft = State(initialValue: OCRTextDraft(result: result))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if fellBackToLocal { fallbackHint }
            textArea
            if showSource { sourceThumb }
            actionBar
        }
        .padding(.top, 30)            // 让出顶部红绿灯按钮区
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(width: 480, height: 560)
        .background(SettingsTheme.card)
        .onAppear {
            // 打开即写入剪贴板——继承旧「截图复制」的零点击习惯；之后改文 / 换排版 / 重识别再点「复制」。
            if !didAutoCopy { copyToPasteboard(draft.text); didAutoCopy = true }
        }
        .background(
            Button(action: onClose) { EmptyView() }
                .keyboardShortcut(.cancelAction)   // Esc 关闭（titled 窗口默认只有 ⌘W）
                .opacity(0).accessibilityHidden(true)
        )
    }

    // MARK: - Header (title + engine picker)

    private var header: some View {
        HStack(spacing: 9) {
            Text("✦").font(.system(size: 13)).foregroundStyle(SettingsTheme.wine)
            Text(AppBrand.displayName)
                .font(SkinMetrics.serif(15.5, weight: .bold))
                .foregroundStyle(SettingsTheme.ink)
            Text("· 截图取字").font(.system(size: 11)).foregroundStyle(SettingsTheme.ink3)
            Spacer(minLength: 8)
            enginePicker
        }
        .padding(.bottom, 12)
    }

    /// 文本识别引擎下拉——换服务商即就地重识别（feature 3）。
    private var enginePicker: some View {
        Menu {
            ForEach(OCREngine.selectableCases) { option in
                Button {
                    guard option != engine else { return }
                    engineRaw = option.rawValue
                    reOCR()
                } label: {
                    if option == engine { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isReOCRing {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else {
                    Image(systemName: engine.isLocal ? "cpu" : "cloud")
                        .font(.system(size: 10))
                }
                Text(pickerLabel(engine)).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(SettingsTheme.ink)
            .padding(.horizontal, 11).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9).fill(chip))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(isReOCRing)
        .help("切换 OCR 引擎并对当前截图重新识别")
    }

    private var fallbackHint: some View {
        Text("该引擎未配置密钥，已用 Apple Vision（本机）识别。")
            .font(.system(size: 11.5)).foregroundStyle(SettingsTheme.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    // MARK: - Editable text

    private var textArea: some View {
        TextEditor(text: Binding(
            get: { draft.text },
            set: { draft.text = $0 }))
            .font(.system(size: 14))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(SettingsTheme.ink.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsTheme.hair, lineWidth: 1))
            .overlay(alignment: .center) {
                if isReOCRing {
                    ProgressView("重新识别中…").controlSize(.small)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(SettingsTheme.card))
                }
            }
            .accessibilityLabel("识别结果，可编辑")
    }

    private var sourceThumb: some View {
        Image(nsImage: sourceImage)
            .resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SettingsTheme.hair, lineWidth: 1))
            .padding(.top, 10)
    }

    // MARK: - Action bar (智能分段 · 字数 · 看原图 · copy)

    /// 智能分段 ↔ 原始分行：主题化双段切换，与截图翻译面板同款——轨底 ink 5%、选中段抬起为暖卡 + 酒红字，
    /// 替掉系统蓝 `.segmented`，配色随皮肤。
    /// ponytail: 与 `SnapTranslatePanelView.modeToggle` 是双胞胎；第三处再要用时再抽共享组件。
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(OCRLayoutMode.allCases, id: \.self) { m in
                Button {
                    draft.select(m)
                } label: {
                    Text(m.label)
                        .font(.system(size: 11.5, weight: draft.mode == m ? .semibold : .regular))
                        .foregroundStyle(draft.mode == m ? SettingsTheme.wine : SettingsTheme.ink2)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(draft.mode == m ? SettingsTheme.card : Color.clear)
                                .shadow(color: .black.opacity(draft.mode == m ? 0.05 : 0), radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(SettingsTheme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        .opacity(supportsSmartParagraphing ? 1 : 0.45)
        .disabled(!supportsSmartParagraphing)
        .help(supportsSmartParagraphing ? "智能分段：合并 OCR 续行" : "当前引擎已完成段落整理，排版切换不可用")
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(SettingsTheme.hair).padding(.top, 12)
            HStack(spacing: 10) {
                modeToggle

                Text("\(draft.characterCount) 字")
                    .font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink3)

                Spacer(minLength: 0)

                Button { showSource.toggle() } label: {
                    Text(showSource ? "隐藏原图" : "看原图").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(SettingsTheme.ink2)

                OCRTextCleanupMenu(
                    draft: draft,
                    undoManager: undoManager,
                    helpText: "整理当前识别文本")

                IconActionButton(systemName: "doc.on.doc", flashSystemName: "checkmark",
                                 enabled: !draft.text.isEmpty, accessibility: "复制文本") {
                    copyToPasteboard(draft.text)
                    return true
                }
            }
            .padding(.top, 11)
        }
    }

    // MARK: - Actions

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// 用当前选中的引擎对同一张截图重新识别（不重新框选）。读钥匙串只发生在这里，不在 `body`。
    private func reOCR() {
        guard !isReOCRing else { return }
        isReOCRing = true
        let chosen = engine
        let provider = RoutedOCRProvider(engine: chosen).resolve()
        // 云端引擎缺密钥时 RoutedOCRProvider 会回落 Apple Vision——靠 provider.id 判断，避免再读一次钥匙串。
        let fellBack = !chosen.isLocal && provider.id == AppleVisionOCRProvider().id
        let img = cgImage
        Task {
            let recognized = try? await provider.recognize(img)
            await MainActor.run {
                if let recognized {
                    draft.replaceResult(recognized)
                    undoManager?.removeAllActions()
                }
                fellBackToLocal = fellBack
                isReOCRing = false
            }
        }
    }

    private func pickerLabel(_ engine: OCREngine) -> String {
        switch engine {
        case .appleVision: "Apple Vision"
        case .paddleOCRLocal: "PaddleOCR"
        case .mistral: "Mistral OCR"
        case .baidu: "百度 OCR"
        }
    }
}
