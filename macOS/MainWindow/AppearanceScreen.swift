import SwiftUI

struct AppearanceScreen: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    @Binding var interfaceLanguage: String

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "外观主题", desc: "定制界面的色彩与风格，多套主题可供选择。")
            skinSelectionCard
            capsuleSkinCard
            languageCard
        }
    }

    private var languageCard: some View {
        WarmCard {
            GroupLabel(text: "界面语言")
            SettingsRow(title: "界面语言", desc: "应用界面显示的语言。") {
                Picker("", selection: $interfaceLanguage) {
                    Text("跟随系统").tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                .labelsHidden().fixedSize()
                .onChange(of: interfaceLanguage) { _, newValue in
                    InterfaceLanguage.apply(newValue)
                }
            }
        }
    }

    // Three flexible columns → a tidy grid (9 skins = 3×3) so each card has real width and the
    // display name never wraps character-by-character. Reflows to as many rows as the skins need.
    private let skinColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    private var skinSelectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配色方案").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
            LazyVGrid(columns: skinColumns, spacing: 14) {
                ForEach(Skin.allCases) { s in
                    SkinSwatchCard(skin: s, isSelected: appearanceStore.skin == s) {
                        withAnimation(.easeInOut(duration: 0.3)) { appearanceStore.skin = s }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }

    // 录音胶囊有自己的外观坐标轴（见 `CapsuleSkin`）：默认「跟随皮肤」＝上面的配色方案，
    // 另外两套是完整的视觉身份，连非录音相位的演法都不同，故不并进配色方案的九宫格。
    private var capsuleSkinCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("录音胶囊外观").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
            Text("听写和提问时浮在屏幕上的那颗胶囊。选「跟随皮肤」则跟着上面的配色方案走。")
                .font(.system(size: SkinMetrics.fsLabel))
                .foregroundStyle(appearanceStore.palette.ink2)
                .padding(.bottom, 10)
            LazyVGrid(columns: skinColumns, spacing: 14) {
                ForEach(CapsuleSkin.allCases) { cs in
                    CapsuleSkinCard(capsuleSkin: cs, isSelected: appearanceStore.capsuleSkin == cs) {
                        withAnimation(.easeInOut(duration: 0.3)) { appearanceStore.capsuleSkin = cs }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }
}
