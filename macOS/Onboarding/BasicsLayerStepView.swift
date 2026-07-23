import SwiftUI
import ResponsayCore

/// 280 — 引导内「装离线基础层」步。基础层 = SenseVoice（听写）+ CT-Transformer（中英标点），
/// 合计约 230 MB，零 key 可离线听写并自动加标点。朗读（Kokoro TTS，约 365 MB）**不是**
/// 基础模型，挪到下方「可选」单独下载。手动开始（产品拍板 2026-06-11：不自动拉）、可跳过
/// 可后补；复用 LocalModelDownloadManager（断点续传 + 磁盘预检都在）。
struct BasicsLayerStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    /// 基础层：听写 + 标点（两者一起构成「零 key 离线听写」的最小集）。
    @State private var basicsManagers: [LocalModelDownloadManager] = [
        LocalModelDownloadManager(spec: LocalModelRegistry.defaultASR),
        LocalModelDownloadManager(spec: LocalModelRegistry.punctuationModel),
    ]
    /// 朗读（TTS）是可选项，单独下载，不计入基础层进度。
    @State private var ttsManager = LocalModelDownloadManager(spec: LocalModelRegistry.defaultTTS)

    private var status: BasicsLayerStatus {
        BasicsLayerStatus(states: basicsManagers.map(\.state))
    }

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 20) {
            OBStepHeader(
                kicker: OnboardingStep.basicsLayer.kicker,
                title: Text("装上").fontWeight(.light) + Text("离线基础层").fontWeight(.semibold),
                lede: "基础层 = 听写 + 中英标点，一次约 230 MB，从此零 key 完全离线听写并自动加标点。朗读为可选项，可单独下载。跳过也行，之后随时能补。")

            VStack(spacing: 12) {
                ForEach(basicsManagers) { manager in
                    modelRow(manager, p)
                }
            }

            actionRow(p)

            ttsSection(p)

            // 诚实能力矩阵：每个 ✓/✗ 都能指到实现 —— 听写 = SenseVoice 引擎、标点 =
            // CT-Transformer（如实输入离线加标点）；朗读需另装可选的 Kokoro 或配云端 TTS；
            // 改写/翻译/地道外文走云端 BYOK provider（需云端 key，无离线改写）。
            VStack(spacing: 0) {
                matrixRow("装好基础层后", "现在", p, header: true)
                Rectangle().fill(p.hair).frame(height: 1)
                matrixRow("中/英听写 + 自动标点（点按听写→上屏）", "✓ 完全离线", p, header: false)
                Rectangle().fill(p.hair).frame(height: 1)
                matrixRow("朗读（选中→自然人声）", "需另装「离线朗读」（下方可选）或配云端 TTS", p, header: false)
                Rectangle().fill(p.hair).frame(height: 1)
                matrixRow("改写 / 翻译 / 地道外文", "✗ 需云端 key", p, header: false)
            }
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))

            Text(model.region == .cn
                 ? "当前下载源：国内镜像优先（第 3 步可改）。跳过后可在 设置 → 存储 或菜单栏「继续首次设置」回来补装。"
                 : "当前下载源：GitHub 官方源（第 3 步可改）。跳过后可在 设置 → 存储 或菜单栏「继续首次设置」回来补装。")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            basicsManagers.forEach { $0.refresh() }
            ttsManager.refresh()
        }
    }

    // MARK: rows

    private func modelRow(_ manager: LocalModelDownloadManager, _ p: SkinPalette, standalone: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: manager.spec.capability))
                .font(.system(size: 20)).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.displayName)
                    .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.ink)
                Text(rowDetail(manager))
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
            }
            Spacer(minLength: 0)
            rowTrailing(manager, p, standalone: standalone)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))
    }

    private func icon(for capability: LocalModelCapability) -> String {
        switch capability {
        case .tts: "speaker.wave.2.circle"
        case .punctuation: "textformat"
        default: "waveform.circle"
        }
    }

    private func role(for capability: LocalModelCapability) -> String {
        switch capability {
        case .tts: "朗读"
        case .punctuation: "标点"
        case .asr: "听写"
        default: ""
        }
    }

    private func rowDetail(_ manager: LocalModelDownloadManager) -> String {
        switch manager.state {
        case .failed(let message): return "下载失败：\(message)"
        default: return "\(role(for: manager.spec.capability)) · \(manager.sizeText)"
        }
    }

    @ViewBuilder private func rowTrailing(_ manager: LocalModelDownloadManager, _ p: SkinPalette, standalone: Bool) -> some View {
        switch manager.state {
        case .installed:
            Label("已装好", systemImage: "checkmark.circle.fill")
                .font(.system(size: SkinMetrics.fsFoot, weight: .semibold)).foregroundStyle(p.accent)
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 90)
                Button("取消") { manager.cancel() }.controlSize(.small)
            }
        case .verifying:
            Text("校验中…").font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
        case .extracting:
            Text("解压中…").font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
        case .failed:
            Button("重试") { manager.download() }.controlSize(.small)
        case .checking, .notInstalled:
            // Base-layer rows share the collective「下载基础层」button below; the optional
            // (standalone) TTS row carries its own download button.
            if standalone {
                Button("下载（\(manager.sizeText)）") { manager.download() }
                    .controlSize(.small).tint(p.accent)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder private func actionRow(_ p: SkinPalette) -> some View {
        if status.allInstalled {
            Label("基础层已就绪 —— 听写与离线标点已完全离线。", systemImage: "checkmark.seal.fill")
                .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.accent)
        } else if status.anyBusy {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: status.fraction)
                Text("正在下载基础层 · 断网会自动断点续传")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    for manager in basicsManagers where manager.state != .installed { manager.download() }
                } label: {
                    Text(status.firstFailure == nil ? "下载基础层（约 230 MB）" : "重试下载基础层")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                }
                .controlSize(.large)
                .tint(p.accent)
                if let failure = status.firstFailure {
                    Text("上次失败：\(failure)")
                        .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Optional 朗读 (Kokoro TTS) — not part of the base layer; download on demand.
    @ViewBuilder private func ttsSection(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可选 · 离线朗读")
                .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.2)
                .foregroundStyle(p.ink3)
            modelRow(ttsManager, p, standalone: true)
        }
    }

    private func matrixRow(_ a: String, _ b: String, _ p: SkinPalette, header: Bool) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(header ? p.ink3 : p.ink)
            Text(b).frame(maxWidth: 300, alignment: .leading)
                .foregroundStyle(header ? p.ink3 : (b.hasPrefix("✓") ? p.accent : p.ink2))
        }
        .font(.system(size: header ? SkinMetrics.fsLabel : SkinMetrics.fsFoot, weight: header ? .bold : .regular))
        .padding(.horizontal, 16).padding(.vertical, header ? 10 : 9)
    }
}
