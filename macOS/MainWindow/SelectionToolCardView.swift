import SwiftUI
import ResponsayCore

/// 技能平台›写作技能›排版整理 里的一张卡：规则驱动的写作技能（如 规范排版），没有 `*.LEGAL_SKILL.md`
/// 背书，所以没有导出 / 编辑 / 标签，只有一个 激活 / 取消激活 开关。激活后对应的 `SelectionAction`
/// 才出现在划词菜单（见 `SelectionMenuGate`）。
/// 视觉与 `LegalSkillCardView` 对齐（同高度 / 同胶囊 / 同 accent 处理），使网格排布统一。
struct SelectionToolCardView: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let tool: SelectionTool
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(tool.title)
                            .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                            .foregroundStyle(appearanceStore.palette.ink)

                        Text("内置")
                            .font(.system(size: SkinMetrics.fsCaption, weight: .medium))
                            .foregroundStyle(appearanceStore.palette.ink3)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().stroke(appearanceStore.palette.hair, lineWidth: 1))

                        if isActive {
                            Text("当前")
                                .font(.system(size: SkinMetrics.fsCaption, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(appearanceStore.palette.accent))
                        }
                    }

                    Text(tool.summary)
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(appearanceStore.palette.ink2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 54, alignment: .top)
                }

                Spacer()

                Image(systemName: tool.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(appearanceStore.palette.card))
            }
            .padding(16)

            Spacer(minLength: 0)

            HStack {
                Button(action: onToggle) {
                    Text(isActive ? "取消激活" : "激活")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                        .foregroundStyle(isActive ? appearanceStore.palette.ink : .white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(isActive ? appearanceStore.palette.card : appearanceStore.palette.accent))
                        .overlay(Capsule().stroke(isActive ? appearanceStore.palette.hair : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(16)
            .background(appearanceStore.palette.card.opacity(0.5))
        }
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                .fill(isActive ? appearanceStore.palette.accent.opacity(0.03) : appearanceStore.palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                .strokeBorder(isActive ? appearanceStore.palette.accent.opacity(0.5) : appearanceStore.palette.hair, lineWidth: isActive ? 2 : 1)
        )
        .cardShadow(.rest)
    }
}
