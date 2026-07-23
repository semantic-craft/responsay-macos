import SwiftUI
import ResponsayCore

/// 翻译语言 card — the Bob-style 第一语言（母语）/ 第二语言（外语） pair that drives translation
/// direction across the app: 听写翻译 / 划词翻译 = 第一 → 第二; 截图翻译「自动」= 外文 → 第一,
/// 第一 → 第二. Replaces the former single「翻译目标语言」picker. (Formerly the 划词互动 card; its
/// hold-and-drag trigger was retired for the Fn+V tap shortcut.)
struct SelectionInteractionSection: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @AppStorage(TranslationTargetSettings.primaryLanguageKey)
    private var primaryRaw = TranslationTargetSettings.defaultPrimary.rawValue
    @AppStorage(TranslationTargetSettings.targetLanguageKey)
    private var secondaryRaw = TranslationTargetSettings.defaultSecondary.rawValue

    var body: some View {
        WarmCard {
            CapabilityHeader(
                systemImage: "character.book.closed",
                title: "翻译语言",
                subtitle: "第一语言是你的母语，第二语言是你最常用的外语。听写翻译、划词翻译把母语译成外语；截图翻译「自动」则把外文译成母语。")
            WarmDivider()

            LabeledRow(label: "第一语言（母语）") {
                languagePicker(selection: $primaryRaw)
            }
            WarmDivider()
            LabeledRow(label: "第二语言（外语）") {
                languagePicker(selection: $secondaryRaw)
            }
            Text("举例（母语=中文、外语=英语）：听写 / 划词翻译 → 英文；截图英文 → 中文，截图中文 → 英文。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languagePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(TranslationTargetLanguage.allCases) { target in
                Text(target.shortSettingsLabel).tag(target.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 160)
    }
}

private extension TranslationTargetLanguage {
    var shortSettingsLabel: String {
        switch self {
        case .englishUS:
            "英语"
        case .german:
            "德语"
        case .japanese:
            "日语"
        case .chineseSimplified:
            "中文"
        }
    }
}
