import AppKit
import SwiftUI
import ResponsayCore

/// 截图翻译 结果面板：原文 → 译文，可切换不同 AI 服务对比、复制译文、对原文智能分段后重译。
/// 建立在 Anamara 识图（`SnapOCRPanelView`）之上，但**不再**复用「地道说法」改写卡——截图翻译就是
/// 翻译，原文/译文双栏。配色走 `SettingsTheme`（→ 当前皮肤）。
///
/// 切换+记忆：顶部「译文服务」选服务即重译；缓存按服务、语言、排版与原文 revision 隔离，编辑原文
/// 只标记旧译文过期。读钥匙串 / 发网络只在注入的 `translate` 闭包里发生，绝不进 `body`
/// ——见 keychain-on-render 冻结教训（与 `reOCR` 同纪律）。
@MainActor
struct SnapTranslatePanelView: View {
    let sourceImage: NSImage?
    let services: [SnapTranslateService]
    /// 把 `text` 解析成目标语言（截图翻译自动定向：外文→母语 / 母语→外语）。
    let resolveTarget: (String) -> TranslationTargetLanguage
    /// 用所选服务翻译 `text`。端点解析（读钥匙串）+ 网络都在闭包内部，不在 `body`。
    let translate: @MainActor (_ text: String, _ serviceId: String, _ target: TranslationTargetLanguage) async -> Result<String, SnapTranslateError>
    var onClose: () -> Void

    @Environment(\.undoManager) private var undoManager
    @State private var session: SnapTranslateSession
    @State private var serviceId: String
    /// 译文语言覆写：`nil` = 跟随自动定向（`resolveTarget`），选定具体语言则钉死。仅本面板内有效，
    /// 不动设置里的全局默认（截图翻译是一次性动作，覆写不该悄悄改全局）。
    @State private var targetOverride: TranslationTargetLanguage?
    @State private var showSource = false
    @State private var didAutoCopy = false
    /// 「重新翻译 ⟳」用：纳入 task id，所以同服务同排版也能强制重跑（并取消在途请求）。
    @State private var refreshNonce = 0

    init(
        original: OCRResult,
        sourceImage: NSImage?,
        services: [SnapTranslateService],
        initialServiceId: String,
        resolveTarget: @escaping (String) -> TranslationTargetLanguage,
        translate: @escaping @MainActor (String, String, TranslationTargetLanguage) async -> Result<String, SnapTranslateError>,
        onClose: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.services = services
        self.resolveTarget = resolveTarget
        self.translate = translate
        self.onClose = onClose
        _session = State(initialValue: SnapTranslateSession(original: original))
        _serviceId = State(initialValue: initialServiceId)
    }

    // MARK: - Derived

    private var draft: OCRTextDraft { session.draft }
    private var supportsSmartParagraphing: Bool { draft.supportsSmartParagraphing }
    private var originalText: String { draft.text }
    private var target: TranslationTargetLanguage { targetOverride ?? resolveTarget(originalText) }
    private var translatedServices: [SnapTranslateService] {
        services.filter { session.hasCachedTranslation(serviceId: $0.id, target: target) }
    }
    private var activeName: String { services.first { $0.id == serviceId }?.name ?? "译文服务" }
    private var taskKey: String {
        "\(serviceId)|\(targetOverride?.rawValue ?? "auto")|\(refreshNonce)"
    }
    private var output: String { session.output }
    private var isTranslating: Bool { session.isTranslating }
    private var errorText: String? { session.errorText }
    private var isTranslationStale: Bool {
        session.isTranslationStale(serviceId: serviceId, target: target)
    }
    private var displayCount: Int { draft.characterCount }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionLabel("原文", trailing: AnyView(sourceActions))
            sourceEditor
            if showSource, let sourceImage { sourceThumb(sourceImage) }
            Spacer(minLength: 14)
            translatedHeader
            translationField
            actionBar
        }
        .padding(18)
        .frame(width: 460)
        .background(SettingsTheme.card)
        .task(id: taskKey) { await runTranslate() }
        .background(
            Button(action: onClose) { EmptyView() }
                .keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Text("✦").font(.system(size: 13)).foregroundStyle(SettingsTheme.wine)
            Text(AppBrand.displayName)
                .font(SkinMetrics.serif(15.5, weight: .bold))
                .foregroundStyle(SettingsTheme.ink)
            Text("· 截图翻译").font(.system(size: 11)).foregroundStyle(SettingsTheme.ink3)
            Spacer(minLength: 8)
            servicePicker
        }
        .padding(.bottom, 12)
    }

    /// 译文服务下拉——切服务即重译（缓存命中则秒回）。
    private var servicePicker: some View {
        Menu {
            ForEach(services) { svc in
                Button {
                    guard svc.id != serviceId else { return }
                    serviceId = svc.id
                } label: {
                    if svc.id == serviceId { Label(svc.name, systemImage: "checkmark") }
                    else { Text(svc.name) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud").font(.system(size: 10)).foregroundStyle(SettingsTheme.ink2)
                Text(activeName).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(SettingsTheme.ink2)
            }
            .foregroundStyle(SettingsTheme.ink)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9).fill(SettingsTheme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(services.isEmpty)
        .help("切换翻译服务并重新翻译；切回已译过的服务会立即显示之前的结果")
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String, trailing: AnyView) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsTheme.ink2)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 6)
    }

    private var sourceToggle: some View {
        Button { showSource.toggle() } label: {
            Text(showSource ? "隐藏原图" : "看原图").font(.system(size: 12))
        }
        .buttonStyle(.plain).foregroundStyle(SettingsTheme.ink2)
    }

    private var sourceActions: some View {
        HStack(spacing: 10) {
            OCRTextCleanupMenu(
                draft: draft,
                undoManager: undoManager,
                helpText: "整理截图翻译原文")
            if sourceImage != nil { sourceToggle }
        }
    }

    /// 译文行表头：「译文 · [语言 ▾]」——语言可点切换目标语言，右侧是已译服务芯片 + 重译。
    private var translatedHeader: some View {
        HStack(spacing: 6) {
            Text("译文").font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsTheme.ink2)
            Text("·").font(.system(size: 12)).foregroundStyle(SettingsTheme.ink3)
            languageMenu
            if isTranslationStale {
                Text("原文已修改").font(.system(size: 11)).foregroundStyle(SettingsTheme.amber)
            }
            Spacer(minLength: 8)
            recallStrip
        }
        .padding(.bottom, 6)
    }

    /// 译文语言切换：自动（按母语/外语方向）或钉死某语言，改即重译（缓存按语言分桶，切回秒回）。
    private var languageMenu: some View {
        Menu {
            Button { targetOverride = nil } label: {
                let autoLabel = "自动（\(targetShort(resolveTarget(originalText)))）"
                if targetOverride == nil { Label(autoLabel, systemImage: "checkmark") } else { Text(autoLabel) }
            }
            Divider()
            ForEach(TranslationTargetLanguage.allCases) { lang in
                Button { targetOverride = lang } label: {
                    if targetOverride == lang { Label(lang.label, systemImage: "checkmark") } else { Text(lang.label) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(targetShort(target)).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).opacity(0.6)
            }
            .foregroundStyle(SettingsTheme.wine)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("选择译文语言；自动＝按你的母语/外语方向判定")
    }

    /// 译文行右侧：已译过的服务芯片（点名字秒切对比）+ 重新翻译。
    private var recallStrip: some View {
        HStack(spacing: 6) {
            if !translatedServices.isEmpty {
                Text("已译").font(.system(size: 11)).foregroundStyle(SettingsTheme.ink3)
                ForEach(translatedServices) { svc in
                    Button { serviceId = svc.id } label: {
                        Text(svc.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(svc.id == serviceId ? SettingsTheme.wine.opacity(0.12) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(svc.id == serviceId ? SettingsTheme.wine.opacity(0.34) : SettingsTheme.hair, lineWidth: 1))
                            .foregroundStyle(svc.id == serviceId ? SettingsTheme.wine : SettingsTheme.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(SettingsTheme.ink2)
            .disabled(isTranslating)
            .help("用当前服务重新翻译")
        }
    }

    // MARK: - Text areas

    private var sourceEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { draft.text },
                set: { draft.text = $0 }))
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(6)
            if originalText.isEmpty {
                Text("（没有识别到文字）")
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsTheme.ink3)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 120)
        .background(RoundedRectangle(cornerRadius: 12).fill(SettingsTheme.ink.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        .accessibilityLabel("截图翻译原文，可编辑")
    }

    private var translationField: some View {
        ScrollView {
            translationContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 240)
        .background(RoundedRectangle(cornerRadius: 12).fill(SettingsTheme.field))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsTheme.hair, lineWidth: 1))
    }

    @ViewBuilder private var translationContent: some View {
        if isTranslating && output.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("翻译中…").font(.system(size: 13)).foregroundStyle(SettingsTheme.ink3)
            }
        } else if let errorText {
            Text(errorText).font(.system(size: 13)).foregroundStyle(SettingsTheme.amber)
        } else {
            Text(output).font(.system(size: 14)).lineSpacing(3)
                .foregroundStyle(isTranslationStale ? SettingsTheme.ink2 : SettingsTheme.ink)
                .textSelection(.enabled)
        }
    }

    private func sourceThumb(_ sourceImage: NSImage) -> some View {
        Image(nsImage: sourceImage)
            .resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SettingsTheme.hair, lineWidth: 1))
            .padding(.top, 8)
    }

    // MARK: - Action bar (智能分段 · 字数 · 复制译文)

    /// 智能分段 ↔ 原始分行：主题化双段切换。替掉系统蓝 `.segmented`——轨底 ink 5%、选中段抬起为
    /// ivory 卡 + 酒红字，配色随皮肤，跟面板暖卡一致（对齐 servicePicker / recallStrip 的语汇）。
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(OCRLayoutMode.allCases, id: \.self) { m in
                Button { draft.select(m) } label: {
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
        .help(supportsSmartParagraphing ? "智能分段：合并 OCR 续行后再翻译" : "当前引擎已完成段落整理，排版切换不可用")
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(SettingsTheme.hair).padding(.top, 12)
            HStack(spacing: 10) {
                modeToggle

                Text("\(displayCount) 字").font(.system(size: 11.5)).foregroundStyle(SettingsTheme.ink3)

                Spacer(minLength: 0)

                IconActionButton(systemName: "doc.on.doc", flashSystemName: "checkmark",
                                 enabled: !output.isEmpty && !isTranslationStale, accessibility: "复制译文") {
                    copyToPasteboard(output)
                    return true
                }
            }
            .padding(.top, 11)
        }
    }

    // MARK: - Actions

    /// 当前 (服务, 分段) 的译文：命中缓存秒回，否则调注入的 `translate` 闭包。首条译文落定即自动复制
    /// 一次（沿用截图取字的零点击习惯，只是这里复制的是译文）。
    private func runTranslate() async {
        if let translated = await session.translate(
            serviceId: serviceId,
            target: target,
            using: translate),
           !didAutoCopy {
            copyToPasteboard(translated)
            didAutoCopy = true
        }
    }

    private func refresh() {
        session.invalidate(serviceId: serviceId, target: target)
        refreshNonce += 1   // task id changes → re-runs (cancelling any in-flight)
    }

    private func copyToPasteboard(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func targetShort(_ lang: TranslationTargetLanguage) -> String {
        switch lang {
        case .chineseSimplified: "中文"
        case .englishUS: "英语"
        case .german: "德语"
        case .japanese: "日语"
        }
    }
}
