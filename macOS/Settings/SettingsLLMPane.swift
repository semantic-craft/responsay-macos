import SwiftUI
import ResponsayCore

struct SettingsLLMPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let llmEngineSelection: Binding<String>

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "文本改写连接配置", desc: "配置改写 LLM 的密钥、端点和模型 ID。")

            SettingsStatusBar {
                StatusDot(state: .green)
                Text("当前文本处理在「设置 · 模型」选择")
                Spacer(minLength: 0)
                Text("这里只配置密钥、端点和模型 ID").foregroundStyle(appearanceStore.palette.ink3)
            }
            CapabilityCardView(capability: .llm, preferredProviderId: currentLLMProviderId)
                .id("llm-config-\(currentLLMProviderId ?? "cloud")")
            Text("改写、翻译、地道外文与讲解共用上面这一路「改写 LLM」配置，直连所选服务商。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .navigationTitle("文本改写连接配置")
    }

    private var currentLLMProviderId: String? {
        llmEngineSelection.wrappedValue
    }
}
