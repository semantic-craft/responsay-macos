import SwiftUI
import ResponsayCore

struct SettingsLegalConfigPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    // 475 — card (default, copy/逐项插入) vs 直接上屏. Read raw by `CaptureController`.
    @AppStorage("legal.outputMode") private var outputMode: LegalOutputModePreference = .card
    // 屏幕上下文 — same key `ScreenContextSettings` reads on the capture path. Default ON.
    @AppStorage(ScreenContextSettings.key) private var screenContext = true

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "技能偏好", desc: "设置技能跑完后的结果输出方式。")

            WarmCard {
                CardHeader(systemImage: "rectangle.and.pencil.and.ellipsis", title: "结果输出方式",
                           subtitle: "技能跑完后，结果放进浮窗，还是直接写到你光标处。", accent: SettingsTheme.cLegal) {
                    Picker("", selection: $outputMode) {
                        Text("卡片").tag(LegalOutputModePreference.card)
                        Text("直接上屏").tag(LegalOutputModePreference.insert)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Text("卡片：进浮窗，可复制、逐项插入。直接上屏：把正文写到光标处或替换选区——密码框等安全输入下始终回退卡片，不上屏。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WarmCard {
                CardHeader(systemImage: "macwindow.on.rectangle", title: "屏幕上下文",
                           subtitle: "让 AI 读懂你当前看到的屏幕，知道你在做什么。", accent: SettingsTheme.cLegal) {
                    Toggle("", isOn: $screenContext).labelsHidden().toggleStyle(.switch)
                }
                Text("开启后，地道外文和任意提问会把当前应用、窗口标题与屏幕可见文字随提问发给你配置的云端 AI（用你自己的 key）；密码框等敏感场景自动跳过。关闭后不再发送任何屏幕内容，本机热词与技能路由不受影响。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // ponytail: 「用户画像」(身份/法域/模型路由/发送范围) 已撤——对单用户是常量、与模型切换器
            // 重复，且发送范围那档从不真捕获附近标题；用户区分改由提示词处理，屏幕上下文开关已覆盖取数。
            // 路由仍以安全默认运行(发送前确认 + 仅选中文本)。背后 LegalPracticeProfile / SQLite store /
            // LegalColdStart 现成孤儿,留待一次专门的清理删除。
            Text("为安全起见，未经核验的法条 / 案例引用始终标注 [待核]；\(AppBrand.displayName)不编造法条号或案号，交由你核实。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .navigationTitle("技能偏好")
    }
}
