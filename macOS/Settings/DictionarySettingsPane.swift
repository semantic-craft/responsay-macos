import AppKit
import SwiftUI
import ResponsayCore

/// 「识别词典」— first-class sidebar pane (issue 321). The cross-cutting hotword
/// asset used by weak terminology hints and post-ASR hard matching, promoted out of the old
/// ASR「高级」disclosure where it sat
/// as a system-styled `Form(.grouped)` island clashing with the warm-paper
/// family. Same stores (`ContextHotwordSettings` / `HotwordStore`), family
/// chrome throughout — no nested Form, no stock blue/red.
struct DictionarySettingsPane: View {
    @Environment(AppearanceStore.self) var appearanceStore
    @AppStorage(ContextHotwordSettings.defaultsKey) var hotwords = ""
    @AppStorage(ContextHotwordSettings.autoDefaultsKey) var autoHotwords = ""
    @AppStorage(AutoLearnHotwordSettings.key) var autoLearnEnabled = false
    @AppStorage(ExplicitCorrectionLearningSettings.key) var explicitCorrectionLearningEnabled = true
    @AppStorage(AutoLearnHotwordHistorySettings.confirmationPolicyKey) var confirmationPolicyRaw = HotwordConfirmationPolicy.autoAddHighConfidence.rawValue
    @AppStorage(AutoLearnHotwordHistorySettings.historyKey) var learningHistoryData = Data()
    @AppStorage(HotwordLLMCorrectionSettings.key) var llmCorrectionEnabled = false
    @AppStorage(CorrectionChipSettings.alwaysShowKey) var correctionChipAlwaysShow = false
    @State var filter: HotwordFilter = .all
    @State var searchText = ""
    @State var newTerm = ""
    @State var editingSource: HotwordSource?
    @State var editingOriginalText = ""
    @State var editingText = ""
    @State var aliasReplayText = ""
    @State var aliasReplayResult: LearnedAliasReplay?
    @State var showClearConfirm = false
    @State var importPreview: DictionaryImportPreview?
    @State var importErrorText: String?

    var dictionaryStore: UserDictionarySettingsStore {
        UserDictionarySettingsStore()
    }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "识别词典", desc: "把术语、人名、案号喂给识别器与教练，并管理自动学习与 AI 纠错。")

            autoLearnStatusBar
            userTermsCard
            llmCorrectionCard
            correctionChipCard
            learningHistoryCard
        }
        .navigationTitle("识别词典")
        .sheet(item: $importPreview) { preview in
            importPreviewSheet(preview)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importErrorText != nil },
            set: { if !$0 { importErrorText = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorText ?? "")
        }
    }

    /// Auto-learn status banner. When 辅助功能 is missing (amber), the whole banner becomes a
    /// button that opens 隐私与权限 so the user can grant it — otherwise it's just a status line.
    @ViewBuilder private var autoLearnStatusBar: some View {
        let bar = SettingsStatusBar {
            StatusDot(state: autoLearnStatusState)
            Text(autoLearnStatusText)
            Spacer(minLength: 0)
            if autoLearnStatusState == .amber {
                Text("去开启 ›")
                    .font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
                    .foregroundStyle(SettingsTheme.wine)
            }
        }
        if autoLearnStatusState == .amber {
            Button { MacSettingsWindowController.shared.show(section: .privacy) } label: { bar }
                .buttonStyle(.plain)
                .help("打开「隐私与权限」，手动开启辅助功能授权")
                .accessibilityLabel("去开启辅助功能授权")
        } else {
            bar
        }
    }

    // MARK: - 语境增强（用户词条）

    private var userTermsCard: some View {
        WarmCard {
            HStack(alignment: .firstTextBaseline) {
                GroupLabel(text: "语境增强")
                Spacer(minLength: 0)
                Button(action: beginImport) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入")
                    }
                    .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                    .foregroundStyle(appearanceStore.palette.ink2)
                }
                .buttonStyle(.plain)
                .help("从 .txt（一行一词）或 .csv（首列为词）文件批量导入词条")
                .accessibilityLabel("从文件批量导入词条")
            }
                    Text("把术语、人名、案号喂给识别器与教练；手动词优先于自动添加。支持热词的云端引擎会按各自机制注入。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)

            SettingsToggleRow(
                title: "自动记住手动纠错",
                desc: "默认开启。你把刚写入的听写词改正一次后，Responsay 会在本机记住原词到正确词的对应关系，后续听写自动应用；无需再次确认，可在下方词典中删除。",
                binding: Binding(
                    get: { explicitCorrectionLearningEnabled },
                    set: { enabled in
                        dictionaryStore.setExplicitCorrectionLearningEnabled(enabled)
                        explicitCorrectionLearningEnabled = dictionaryStore.explicitCorrectionLearningEnabled
                    }))

            SettingsToggleRow(
                title: "自动学习热词",
                desc: "开启后，Responsay 会从你纠正刚写入文本的动作中学习候选词。关闭后停止学习新热词，只使用手动词、内置词和已保留的自动词。",
                binding: Binding(
                    get: { isAutoLearnEnabled },
                    set: { enabled in
                        dictionaryStore.setAutoLearnEnabled(enabled)
                        refreshDictionaryBindings()
                    }))

            autoLearnControls

            filterChips

            HStack(spacing: 8) {
                WarmField(placeholder: "搜索词条", text: $searchText)
                WarmField(placeholder: "新词", text: $newTerm)
                    .frame(width: 170)
                    .onSubmit(addManualTerm)
                Button(action: addManualTerm) {
                    Image(systemName: "plus")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
                        .foregroundStyle(appearanceStore.palette.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(appearanceStore.palette.accent))
                }
                .buttonStyle(.plain)
                .help("添加手动词条")
                .disabled(cleanNewTerm.isEmpty)
                .opacity(cleanNewTerm.isEmpty ? 0.4 : 1)
            }

            termList
        }
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(HotwordFilter.allCases, id: \.self) { option in
                let isOn = filter == option
                Button { filter = option } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(option.title) \(count(for: option))")
                            .font(.system(size: SkinMetrics.fsLabel, weight: isOn ? .semibold : .regular))
                    }
                    .foregroundStyle(isOn ? appearanceStore.palette.onAccent : appearanceStore.palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(isOn
                        ? AnyShapeStyle(appearanceStore.palette.accent)
                        : AnyShapeStyle(appearanceStore.palette.card2)))
                    .overlay(Capsule().strokeBorder(
                        isOn ? .clear : appearanceStore.palette.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var autoLearnControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("候选策略")
                    .font(.system(size: SkinMetrics.fsFoot, weight: .medium))
                    .foregroundStyle(appearanceStore.palette.ink)
                Picker("", selection: Binding(
                    get: { confirmationPolicyRaw },
                    set: { raw in
                        guard let policy = HotwordConfirmationPolicy(rawValue: raw) else { return }
                        dictionaryStore.setConfirmationPolicy(policy)
                        confirmationPolicyRaw = dictionaryStore.confirmationPolicy.rawValue
                    }
                )) {
                    Text("每次确认").tag(HotwordConfirmationPolicy.confirmEveryTime.rawValue)
                    Text("高置信自动加入").tag(HotwordConfirmationPolicy.autoAddHighConfidence.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()  // size to content — a hard width clips/overlaps the longer English labels
                Spacer(minLength: 0)
            }
            .disabled(!isAutoLearnEnabled)
            .opacity(isAutoLearnEnabled ? 1 : 0.45)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var termList: some View {
        if filteredTerms.isEmpty {
            Text("暂无词条——划词时点「加入词典」，或在上方直接添加。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredTerms, id: \.text) { term in
                        termRow(term)
                    }
                }
                .padding(1)
            }
            .frame(minHeight: 96, maxHeight: 200)
        }
    }

    private func termRow(_ term: HotwordTerm) -> some View {
        HStack(spacing: 8) {
            Image(systemName: term.source == .auto ? "sparkle" : "pencil")
                .font(.system(size: SkinMetrics.fsCaption))
                .foregroundStyle(appearanceStore.palette.ink3)
                .frame(width: 18)
                .help(term.source == .auto ? "自动添加" : "手动添加")
            if isEditing(term) {
                WarmField(placeholder: "词条", text: $editingText, mono: false)
                    .onSubmit(saveEditingTerm)
                iconButton("checkmark", help: "保存编辑", action: saveEditingTerm)
                    .disabled(cleanEditingText.isEmpty)
                    .opacity(cleanEditingText.isEmpty ? 0.35 : 1)
                iconButton("xmark", help: "取消编辑", action: cancelEditing)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.text)
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(appearanceStore.palette.ink)
                        .lineLimit(1)
                    if let detail = termDetail(term) {
                        Text(detail)
                            .font(SettingsTheme.footnote)
                            .foregroundStyle(appearanceStore.palette.ink3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                iconButton("pencil", help: "编辑词条") {
                    beginEditing(term)
                }
                iconButton("trash", help: "删除词条") {
                    delete(term)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .fill(appearanceStore.palette.field))
    }

    func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: SkinMetrics.fsCaption))
                .foregroundStyle(appearanceStore.palette.ink3)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - AI 纠错（可选，默认关）

    private var llmCorrectionCard: some View {
        WarmCard {
            GroupLabel(text: "AI 纠错（可选）")
            Text("听写完成后，如果你教过的某个术语被听成了音近的别字，可以让你配置的 AI 再校一遍——只动这些术语，别的字一个都不改。默认关闭：开着、且配好了改写 LLM（自带云端 Key）、且这句话里确实还有音近误识时，才会把已在本机纠过一遍的这句话发给你配的云端模型；关着就完全不出本机。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)

            SettingsToggleRow(
                title: "用 AI 校正术语",
                desc: "只在仍有音近误识的术语时才调用；没有就不发送、不调用，其它内容一律不改。",
                binding: $llmCorrectionEnabled)
        }
    }

    // MARK: - 纠正胶囊

    private var correctionChipCard: some View {
        WarmCard {
            GroupLabel(text: "纠正胶囊")
            Text("听写插入后，「纠正…」入口默认只在这句话像是听错了专有名词（英文大写词、内部大写、数字连字符等形状）时才出现；打开后每句话都会显示，方便你随时手动纠正并让 app 学会。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)

            SettingsToggleRow(
                title: "每次听写都显示纠正入口",
                desc: "关闭时只在疑似专名听错时提示；打开后每句话都能手动纠正并学习。",
                binding: $correctionChipAlwaysShow)
        }
    }

}

enum HotwordFilter: CaseIterable {
    case all, auto, manual

    var title: String {
        switch self {
        case .all: return "所有"
        case .auto: return "自动添加"
        case .manual: return "手动添加"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "circle.grid.2x2"
        case .auto: return "sparkle"
        case .manual: return "pencil"
        }
    }
}
