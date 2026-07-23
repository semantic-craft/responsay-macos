import SwiftUI

/// 法律 AI — a section parallel to 模型提供商.
/// Config-only; the actual verification runs from the hotkey/selection flow.
struct SourceVerificationPane: View {
    @AppStorage("verify.legalProvider") private var legalProvider = "delilegal"
    @AppStorage("verify.legalBaseURL") private var legalBaseURL = ""
    @State private var legalKey = ""

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "法律 AI", desc: "配置专业法律检索增强服务的密钥（预留，暂未启用）。")
            legalAICard
        }
        .navigationTitle("法律 AI")
    }

    /// 按所选提供商存取 key（得理/元典并列，各自 Keychain account）。
    private var legalKeychainAccount: String {
        legalProvider == "delilegal" ? "byok.delilegal" : "byok.yuandian"
    }

    private var legalAICard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WarmCard {
                CapabilityHeader(systemImage: "building.columns", title: "法律 AI 提供商",
                                 subtitle: "专业法律检索增强服务（自带密钥 · 预留，暂未启用）")
                WarmDivider()
                LabeledRow(label: "提供商") {
                    Picker("", selection: $legalProvider) {
                        Text("得理（delilegal）").tag("delilegal")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                LabeledRow(label: "Base URL") {
                    WarmField(placeholder: "platform.delilegal.com", text: $legalBaseURL)
                }
                LabeledRow(label: "API Key") {
                    SecureKeyField(placeholder: "open.delilegal.com/personal/keys 申请", text: $legalKey)
                }
                // 299 决策 B（2026-06-11）：得理接线尚未启用（端点两代需真 key 定版），
                // 文案不得暗示「配了 key 即生效」。key 照存，待接线后改回增强表述。
                Text("预留配置，暂未接入：当前来源核验一律使用本地提取 + 跳转公开权威网站（无论是否填 key）。填入的 key 会安全保存在钥匙串，待得理检索接通后自动启用。")
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(SettingsTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WarmCard {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("元典 · 法律大模型")
                            .font(SettingsTheme.bodyFont).foregroundStyle(SettingsTheme.ink)
                        Text("接入后可直接做法条溯源与类案比对（含幻觉检测）。")
                            .font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    SoonChip()
                }
            }
            .opacity(0.72)
        }
        .onAppear {
            if legalProvider == "yuandian" { legalProvider = "delilegal" }   // 元典 now coming-soon, not selectable
            legalKey = BYOKKeychain.read(legalKeychainAccount) ?? ""
        }
        .onChange(of: legalKey) { _ in BYOKKeychain.write(legalKey, account: legalKeychainAccount) }
        .onChange(of: legalProvider) { _ in legalKey = BYOKKeychain.read(legalKeychainAccount) ?? "" }
    }
}
