import SwiftUI
import ResponsayCore

/// 380 · 设置·改写设置 — the rewrite/coach preferences that used to live in the main
/// window「表达改写」left column. Everyone goes to settings more than the main panel, so
/// configuration belongs here. Reads/writes the exact same UserDefaults keys as before
/// (`RewriteStyleSettings` / `CoachRegisterSettings` / `rewrite.*`), so behavior is
/// unchanged — only the home moved.
struct SettingsRewritePane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    /// 切到设置内另一个区段(不开新窗)，由 `SettingsView` 注入 `{ selection = $0 }`。
    /// 417 — 「打开技能库」按此切到 技能库(日常办公)。
    let openSection: (SettingsSection) -> Void

    // The English Coach's parallel axis (教练语域 / CoachRegister) — distinct from 改写风格.
    @AppStorage(CoachRegisterSettings.key) private var coachRegister = CoachRegister.casual.rawValue
    // 地道外文 输出方式 (412): 直接写入 (no card) / 写入并讲解 / 仅讲解. Drives the capture
    // pipeline via `ExpressInsertSettings.mode().outputMode`. Legacy `expressAutoInsert` bool is
    // migrated into this key on appear so the chips show the user's prior choice.
    @AppStorage(ExpressInsertSettings.key) private var expressOutputRaw = ExpressOutputMode.writeAndExplain.rawValue
    private var expressOutputMode: ExpressOutputMode { ExpressOutputMode(rawValue: expressOutputRaw) ?? .writeAndExplain }
    // 听写默认力度: 轻度改写 (auto-tidy, default) vs 如实 (verbatim opt-out). Same key the
    // menu-bar「如实输入」toggle drives (`DictationRewriteSettings`), so picking here and
    // toggling there stay in sync. Default = 轻度改写 (clean).
    @AppStorage(DictationRewriteSettings.key) private var lightRewrite = true
    /// Built-in 意图成稿 preset. Optional because nil is the default 智能整理; an unknown id means
    /// an imported style is active and is surfaced as such below the built-in choices.
    @State private var dictationStyleID: String? = nil
    // 校验成稿（实验，558）: 在意图成稿档上叠加的 Intent-aware Dictate。默认关；如实输入档不受影响。
    @AppStorage(IntentDictationSettings.key) private var intentAware = false
    // 564: 校验成稿的可选第二阶段润色。默认关——关着时 sanitized draft 就是完整路线。
    @AppStorage(IntentDictationSettings.optionalPolishKey) private var intentOptionalPolish = false
    // 改写策略 (420): 原意优先 (default) vs 猜测意图 — orthogonal to 语气, drives the express
    // prompt via `ExpressRewriteStrategySettings` → SettingsBackedCoachAPI. Default faithful.
    @AppStorage(ExpressRewriteStrategySettings.key) private var rewriteStrategy = ExpressRewriteStrategy.faithful.rawValue
    // P1 风格学习: learn a one-line style descriptor from kept dictations, feed it into 意图成稿.
    @AppStorage(StyleProfileSettings.enabledKey) private var styleEnabled = true
    @AppStorage(StyleProfileSettings.learnedKey) private var styleLearned = ""
    @AppStorage(StyleProfileSettings.overrideKey) private var styleOverride = ""
    // 任意提问联网搜索: opt-in only, because the query is sent to the provider's web-search tool
    // (or to the独立检索服务). 搜索来源与联网模型的选择都在 `WebSearchSourceSection` 里。
    @AppStorage(VoiceAssistantWebSearchSettings.key) private var askWebSearchEnabled = false
    // 566: 校验成稿的编译路线（云端 / 本机 / 未配置），从当前已配置的文本 endpoint 派生。用户「选本机」
    // 只是把「模型与密钥」指向本机 runner；这里让路线对用户可见（spec #30/#59）。刷新于面板出现时。
    @State private var intentRoute: IntentCompilerRoute = .unavailable

    /// The cloud / local / no-key route pill under the 校验成稿 toggle. Content-free (provider id
    /// only), resolved from the configured text endpoint when the row appears.
    private var intentRouteRow: some View {
        HStack(spacing: 8) {
            Image(systemName: intentRoute.isLocal
                ? "desktopcomputer"
                : (intentRoute == .unavailable ? "exclamationmark.triangle" : "cloud"))
                .font(.system(size: 11))
            Text("成稿路线 · \(intentRoute.displayLabel)")
                .font(SettingsTheme.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(intentRoute == .unavailable ? appearanceStore.palette.ink3 : appearanceStore.palette.ink2)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(SettingsTheme.card2))
        .onAppear { intentRoute = IntentCompilerRoute.classify(LLMEndpointResolver.resolveText()) }
        .accessibilityLabel("校验成稿编译路线：\(intentRoute.displayLabel)")
    }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "改写设置", desc: "调整听写改写力度、地道外文与任意提问的联网搜索。")

            WarmCard {
                CapabilityHeader(
                    systemImage: "wand.and.stars",
                    title: "改写力度",
                    subtitle: "听写的两档。默认「意图成稿」：补标点、去口癖、删改口，按你的意图把话理顺、口述清单自动分点；想只用语音原文不过大模型，切到「如实输入」。")
                WarmDivider()
                HStack(spacing: 6) {
                    forceChip("如实输入", "逐字上屏", active: !lightRewrite) { lightRewrite = false }
                    forceChip("意图成稿", "理顺成稿", active: lightRewrite) { lightRewrite = true }
                }
                Text("这里只管听写，二选一（和菜单栏「如实输入」联动）。装好后默认意图成稿：补标点、去口癖、删掉你改口被推翻的话，按你的意图把话理顺，口述的清单还会自动分点——读起来像你认真打的字（但不会替你编事实、加称呼署名或拔高确定性）。如果不认同我们的整理，切到「如实输入」，就只用语音识别原文、不过大模型。选中文字后的「改写选中文本」是另一回事：它跟着选区走、不受这里影响，改写风格在技能平台的「写作技能」里选。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                WarmDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("意图成稿方式")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                        .foregroundStyle(appearanceStore.palette.ink)
                    HStack(spacing: 6) {
                        ForEach(DictationDraftPreset.allCases, id: \.self) { preset in
                            dictationPresetChip(preset)
                        }
                    }
                    Text("「智能整理」保持默认力度；「强制清单」会把两项以上内容整理成编号清单；「正式表达」会改成克制的商务书面语。三者只影响意图成稿。")
                        .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !DictationDraftPreset.contains(styleID: dictationStyleID) {
                        Text("当前使用的是已导入风格。选择上方任一内置方式即可替换。")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.accent)
                    }
                    if intentAware && !intentOptionalPolish {
                        Text("当前已开启「校验成稿」但未开启「成稿后再润色」，所选方式会保留，但暂不参与这一条校验路线。")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!lightRewrite)
                .opacity(lightRewrite ? 1 : 0.45)
                WarmDivider()
                SettingsToggleRow(
                    title: "校验成稿（实验）",
                    desc: "绝大多数情况（约 98%）用默认的「意图成稿」就够了——它同样能懂改口、口述人名释字和各种口头指令，而且更快。这个实验档是给「宁可被打断、也绝不能写错」的场合准备的：模型先给出结构化整理计划，逐条对回你的原话、通过来源校验后才上屏，校验不过就停在胶囊里等你确认——代价是偶尔更慢、更容易被打断，好处是错字永远进不了你的文档。需要已配置文本模型；「如实输入」不受影响，随时可切回。",
                    binding: $intentAware)
                    .disabled(!lightRewrite)
                    .opacity(lightRewrite ? 1 : 0.45)
                if lightRewrite && intentAware { intentRouteRow }
                SettingsToggleRow(
                    title: "成稿后再润色（实验）",
                    desc: "校验成稿通过校验后，再按当前 App 语体和你的风格轻润一遍措辞。润色版还要再过一次安全校验：数字、名字、语言不变才用它；不过就用已校验的原稿。关闭时直接上已校验原稿。",
                    binding: $intentOptionalPolish)
                    .disabled(!lightRewrite || !intentAware)
                    .opacity(lightRewrite && intentAware ? 1 : 0.45)
                WarmDivider()
                Button { openSection(.legalSkills) } label: {
                    Label("管理导入风格与写作技能 →", systemImage: "square.grid.2x2")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(appearanceStore.palette.accent)
                Text("内置的意图成稿方式已在上方选择；技能平台只负责导入的扩展风格和跟着选区走的写作技能。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WarmCard {
                CardHeader(systemImage: "person.bubble", title: "你的表达风格",
                           subtitle: "从你保留的听写里学一句你的风格，喂给「意图成稿」，让它整理得更像你写的。可手改或关掉。", accent: SettingsTheme.wine)
                WarmDivider()
                SettingsToggleRow(
                    title: "学习我的表达风格",
                    desc: "开启后会用你配置的文本模型，偶尔把你近期保留的听写提炼成一句风格描述，叠进意图成稿（默认开）。",
                    binding: $styleEnabled)
                if styleEnabled {
                    WarmDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已学到的风格")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                        Text(styleLearned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "还没学到——多用几次听写，或点下面「重新学习」。"
                             : styleLearned)
                            .font(.system(size: SkinMetrics.fsFoot))
                            .foregroundStyle(appearanceStore.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LabeledRow(label: "手动覆盖") {
                        WarmField(placeholder: "留空=用学到的；填了=用你写的", text: $styleOverride)
                    }
                    Button { StyleProfileRefresher.scheduleIfNeeded(force: true) } label: {
                        Label("重新学习 →", systemImage: "arrow.clockwise")
                            .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appearanceStore.palette.accent)
                    Text("「重新学习」在后台用模型重提炼一次（需要已配好文本模型、且攒够几条听写），完成后这里会刷新。手动覆盖优先于学到的；想关就关掉上面的开关。")
                        .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WarmCard {
                CardHeader(systemImage: "character.bubble", title: "地道外文",
                           subtitle: "把不顺的英文改成母语者会自然说的英文，并解释为什么；中文只作意图兜底，中文出英文优先用翻译。", accent: SettingsTheme.wine)
                WarmDivider()
                // 语气 × 改写策略 — the two "how it rewrites" knobs, paired (no divider between);
                // 输出方式 (how it's delivered) sits below the divider.
                LabeledRow(label: "语气") {
                    Picker("", selection: $coachRegister) {
                        ForEach(CoachRegister.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                }
                LabeledRow(label: "改写策略") {
                    Picker("", selection: $rewriteStrategy) {
                        ForEach(ExpressRewriteStrategy.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                }
                Text("这一档只管「地道外文」——把话转成外语时老实按你说的意思来、还是你说乱时替你重构意图，跟上面听写的「如实 / 意图成稿」是两条线。「原意优先」只换说法、不改你的意思；「猜测意图」在你说乱、说反时，替你把最想表达的那件事理顺，再用母语者的口吻说出来（讲解里会告诉你它怎么理解你的）。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                WarmDivider()
                HStack(spacing: 6) {
                    forceChip("写入并讲解", "默认", active: expressOutputMode == .writeAndExplain) {
                        expressOutputRaw = ExpressOutputMode.writeAndExplain.rawValue
                    }
                    forceChip("仅讲解", "手动写入", active: expressOutputMode == .explainOnly) {
                        expressOutputRaw = ExpressOutputMode.explainOnly.rawValue
                    }
                }
                Text("「写入并讲解」在写入的同时显示讲解卡片（红绿对照、为什么这样说、别的说法）；「仅讲解」只显示讲解卡片，读后再手动写入；两种的讲解内容一致。只想把地道外文直接写进光标、不看讲解，用「听写翻译」（Fn+Shift）即可——它按你的意图直接译成地道外文写入，不弹讲解卡。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WarmCard {
                CardHeader(systemImage: "globe", title: "任意提问",
                           subtitle: "给随手语音问答单独开联网搜索；只作用于「任意提问」，不改变听写、改写、翻译或地道外文。", accent: SettingsTheme.wine)
                WarmDivider()
                SettingsToggleRow(
                    title: "联网搜索",
                    desc: "打开后，这一问会先联网再作答。来源可以是一个独立的检索服务（豆包搜索 / Perplexity，填自己的 Key），也可以跟随模型自带的联网能力。",
                    binding: $askWebSearchEnabled)
                if askWebSearchEnabled {
                    WarmDivider()
                    WebSearchSourceSection()
                }
            }
        }
        .navigationTitle("改写设置")
        // Normalize the retired `expressAutoInsert` bool into the new 3-state key so the chips
        // show the user's prior choice (写入并讲解 / 仅讲解) instead of the bare default.
        .onAppear {
            ExpressInsertSettings.setMode(ExpressInsertSettings.mode())
            dictationStyleID = StyleLaneSettings.activeID(.dictation)
        }
    }

    /// 如实 / 轻改写 — the two listening defaults, mutually exclusive. Tapping flips
    /// `DictationRewriteSettings.key`, the same key the menu-bar「如实输入」toggle drives, so
    /// the two surfaces never drift. The active one is filled + outlined in the accent.
    private func forceChip(_ title: String, _ sub: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipBody(title, sub, titleColor: active ? SettingsTheme.wine : SettingsTheme.ink)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(active ? SettingsTheme.wineTint : SettingsTheme.field))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(active ? SettingsTheme.wine : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func dictationPresetChip(_ preset: DictationDraftPreset) -> some View {
        forceChip(preset.title, preset.subtitle, active: preset.matches(activeStyleID: dictationStyleID)) {
            preset.activate()
            dictationStyleID = preset.styleID
        }
    }

    private func chipBody(_ title: String, _ sub: String, titleColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: SkinMetrics.fsLabel, weight: .medium)).foregroundStyle(titleColor)
            Text(sub).font(.system(size: SkinMetrics.fsCaption)).foregroundStyle(SettingsTheme.ink3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

}
