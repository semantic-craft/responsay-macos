import ResponsayCore
import SwiftUI

// MARK: - 实操体验 · guided sandbox sequence (spec §4.2)

/// Walks `SandboxSequence` flow by flow. Every flow is hands-on (real keys); only the result is a
/// labelled 示例 when no model is configured. The per-flow views are split out
/// (`SandboxDictateFlow` / `SandboxSpokenFlow` / `SandboxVerifyFlow`); this driver only owns
/// the sequence, the speech-auth probe, progress and nav.
struct SandboxStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    @State private var speechAuthorized: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OBStepHeader(
                kicker: OnboardingStep.sandbox.kicker,
                title: Text("上手").fontWeight(.light) + Text("体验").fontWeight(.semibold),
                lede: "一步步亲手试一遍：听写是真的——你说什么就上什么；语音翻译、任意提问、来源核验也按真实快捷键操作，结果先看示例，配好模型后就是实时的。")

            if let flow = model.sandboxSequence.current {
                progressHeader(flow)
                flowView(flow)
                skipRow()
            } else {
                doneCard()
            }
        }
        .onAppear {
            guard speechAuthorized == nil else { return }
            Task { speechAuthorized = await SandboxDictation.requestAuthorization() }
        }
    }

    @ViewBuilder private func flowView(_ flow: SandboxFlow) -> some View {
        switch flow {
        case .dictate:
            SandboxDictateFlow(model: model, speechAuthorized: speechAuthorized)
        case .translate:
            SandboxSpokenFlow(startGesture: .fnShift,
                              instruction: "在微信里按 Fn Shift 说中文，再按 Fn 结束，英文译文直接进聊天框。",
                              spokenExample: "我今天下午把修订版保密协议发过去，争议解决条款还要中国法团队确认。",
                              listeningLabel: "正在听中文 · 再按 Fn 结束",
                              thinkingLabel: "翻译中…",
                              resultLabel: "译文（写入聊天框）",
                              resultText: "I'll send over the revised NDA this afternoon. The dispute-resolution clause still needs confirmation from our China law team.",
                              serifResult: true)
        case .ask:
            SandboxSpokenFlow(startGesture: .fnSpace,
                              instruction: "在任意文档里划选一段，按 Fn Space 问它一句，再按 Fn 结束，回答出现在只读答卡里（朗读 / 复制 / 追问）。",
                              spokenExample: "就选中这段，整理庭审争议焦点。",
                              listeningLabel: "正在听问题 · 再按 Fn 结束",
                              thinkingLabel: "整理回答…",
                              resultLabel: "回答（只读答卡）",
                              resultText: "争议焦点：\n1. 甲方是否已按约交付、是否构成逾期\n2. 逾期是否超过 30 日、是否触发解除条件\n3. 乙方解除权的行使是否在合理期限内\n4. 「双倍返还定金」的主张能否成立",
                              serifResult: false,
                              selectionPassage: "甲方应于 2024 年 3 月 31 日前交付全部货物；逾期超过 30 日的，乙方有权解除合同并要求双倍返还定金。")
        case .verify:
            SandboxVerifyFlow()
        }
    }

    private func progressHeader(_ flow: SandboxFlow) -> some View {
        let p = appearance.palette
        return HStack(spacing: 8) {
            Text(model.sandboxSequence.progress)
                .font(.system(size: SkinMetrics.fsLabel, weight: .bold, design: .monospaced))
                .foregroundStyle(p.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(p.accent))
            Text(displayTitle(flow))
                .font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
            Spacer(minLength: 0)
        }
    }

    private func displayTitle(_ flow: SandboxFlow) -> String {
        switch flow {
        case .dictate:   "听写"
        case .translate: "语音翻译"
        case .ask:       "任意提问"
        case .verify:    "来源核验"
        }
    }

    /// Forward/back is the wizard footer's 继续/返回 (which now walk the 5 flows). The only
    /// sandbox-local affordance is bailing out of the whole step.
    private func skipRow() -> some View {
        let p = appearance.palette
        return HStack {
            Button("跳过实操") { model.next() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(p.ink3)
            Spacer(minLength: 0)
            Text("用下方「继续」逐个体验")
                .font(.system(size: 11)).foregroundStyle(p.ink3)
        }
    }

    private func doneCard() -> some View {
        let p = appearance.palette
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(MacPalette.inserted)
            Text("都试过了！正式使用时，用你刚设的快捷键随处唤起。")
                .font(.system(size: SkinMetrics.fsBody, weight: .semibold)).foregroundStyle(p.ink)
            Button("再试一遍") { model.sandboxSequence = SandboxSequence() }.buttonStyle(.bordered).controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
    }
}
