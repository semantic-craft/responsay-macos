import ResponsayCore
import SwiftUI

// MARK: - 3 · 选引擎（离线 vs 云端能力详解）

struct EngineStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel
    // capability, offline, cloud
    // 改写 / 翻译 / 地道外文 / 法律技能均走云端 BYOK provider（无离线改写）；
    // 本地引擎仅覆盖听写与朗读。
    private let caps: [(String, String, String)] = [
        ("听写 中/英", "✓ 离线·免密钥", "✓ 更准·流式"),
        ("基础改写 / 翻译", "✗ 需云端 Key", "✓ 更地道"),
        ("法律技能改写", "✗ 需云端 Key", "✓ 自带 Key"),
        ("地道外文", "✗ 需云端 Key", "Native +讲解"),
        ("来源核验·URL 直查", "✗ 需联网", "✓"),
        ("自然 TTS", "本地 Kokoro", "多音色·流式")
    ]

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 20) {
            OBStepHeader(
                kicker: OnboardingStep.engine.kicker,
                title: Text("选择语音").fontWeight(.light) + Text("引擎").fontWeight(.semibold),
                lede: "听写与朗读在哪里发生：本地够用又私密；改写、核验等走云端（自带 Key）。")
            VStack(spacing: 12) {
                OBOptionCard(title: "本地引擎",
                             detail: "中英文模型在这台 Mac 上跑，离线、私密、免密钥。首次先用系统听写，离线模型可稍后在 设置 →「离线模型下载与管理」一键下载。",
                             meta: "本机 · 私密",
                             isSelected: model.engine == .local) { model.engine = .local }
                OBOptionCard(title: "云端引擎（自带 Key）",
                             detail: "接你自己的云端大模型，更准更强，解锁来源核验等。需联网、音频加密上传。",
                             meta: "自带密钥 · 最强",
                             isSelected: model.engine == .cloud) { model.engine = .cloud }
            }

            // 280: 国内/海外 一次选择 —— 驱动 sherpa 下载镜像。
            // onAppear 把（按系统 locale）预选的值真正落盘一次，用户不碰也生效。
            HStack(spacing: 10) {
                Image(systemName: "network").font(.system(size: 13)).foregroundStyle(p.accent)
                Text("网络环境").font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.ink)
                Picker("", selection: Binding(get: { model.region }, set: { model.region = $0 })) {
                    ForEach(NetworkRegion.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer(minLength: 0)
                Text(model.region.detail)
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.hair, lineWidth: 1))
            // First choice only: re-running the wizard (菜单栏「重看新手引导」)
            // must not clobber an old user's manual mirror override.
            .onAppear { if NetworkRegion.stored(in: .standard) == nil { NetworkRegion.select(model.region) } }

            // offline-vs-cloud capability table
            VStack(spacing: 0) {
                capRow("能力", "离线", "云端", p, header: true)
                ForEach(caps, id: \.0) { c in
                    Rectangle().fill(p.hair).frame(height: 1)
                    capRow(c.0, c.1, c.2, p, header: false)
                }
            }
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))

            if model.engine == .cloud {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill").font(.system(size: 13)).foregroundStyle(p.accent)
                    Text("配置云端模型：选服务方 → 粘贴 API Key → 测试连接。每家都有图文教程。")
                        .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    Spacer(minLength: 0)
                    Text("看教程 ↗").font(.system(size: SkinMetrics.fsFoot, weight: .semibold)).foregroundStyle(p.accent)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.accentWash))
                .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.accentLine, lineWidth: 1))
            }
        }
    }

    @ViewBuilder private func capRow(_ a: String, _ b: String, _ c: String, _ p: SkinPalette, header: Bool) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(header ? p.ink3 : p.ink)
            Text(b).frame(width: 110, alignment: .leading).foregroundStyle(p.ink2)
            Text(c).frame(width: 120, alignment: .leading).foregroundStyle(p.accent)
                .fontWeight(header ? .bold : .medium)
        }
        .font(.system(size: header ? SkinMetrics.fsLabel : SkinMetrics.fsFoot, weight: header ? .bold : .regular))
        .padding(.horizontal, 16).padding(.vertical, header ? 10 : 9)
    }
}
