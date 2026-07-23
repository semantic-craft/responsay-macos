// Extracted from LegalSkillsScreen.swift (416) to keep both files ≤ 400 lines.
import SwiftUI
import ResponsayCore

struct LegalSkillCardView: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    
    let skill: LegalSkillCompiled
    let isBuiltin: Bool
    let isActive: Bool
    /// The lane's built-in fallback (写作 lane 的 表达升级): shown so the user can see what runs when
    /// nothing is picked. Badged「内置默认」instead of「内置」, and tapping it clears the lane rather
    /// than storing a selection — selecting it would otherwise be indistinguishable from no pick.
    var isDefaultFallback: Bool = false
    let onToggle: () -> Void
    let onExport: () -> Void
    /// Imported skills only — built-ins pass `nil`, which hides 编辑.
    let onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header area
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(skill.metadata.title)
                            .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                            .foregroundStyle(appearanceStore.palette.ink)
                        
                        HStack(spacing: 4) {
                            Text(isDefaultFallback ? "内置默认" : (isBuiltin ? "内置" : "第三方"))
                                .font(.system(size: SkinMetrics.fsCaption, weight: .medium))
                                .foregroundStyle(appearanceStore.palette.ink3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().stroke(appearanceStore.palette.hair, lineWidth: 1))
                            
                            if isActive {
                                Text(isDefaultFallback ? "当前生效" : "当前")
                                    .font(.system(size: SkinMetrics.fsCaption, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(appearanceStore.palette.accent))
                            }
                        }
                    }
                    
                    Text(skill.metadata.description ?? "没有提供说明。")
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(appearanceStore.palette.ink2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 54, alignment: .top) // Fixed approx height for 3 lines
                }
                
                Spacer()
                
                if let icon = skill.metadata.icon, !icon.isEmpty {
                    Text(icon)
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(appearanceStore.palette.card))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(appearanceStore.palette.ink3)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(appearanceStore.palette.card))
                }
            }
            .padding(16)
            
            // Tags area
            let tags = skill.metadata.tags
            if !tags.isEmpty {
                HStack {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(SettingsTheme.cLegal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(SettingsTheme.cLegal.opacity(0.1)))
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(appearanceStore.palette.ink3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 16)
            }
            
            Spacer(minLength: 0)
            
            // Action bar
            HStack {
                Button(action: onToggle) {
                    Text(isActive ? "取消激活" : "激活")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                        .foregroundStyle(isActive ? appearanceStore.palette.ink : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(isActive ? appearanceStore.palette.card : appearanceStore.palette.accent)
                        )
                        .overlay(
                            Capsule().stroke(isActive ? appearanceStore.palette.hair : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: onExport) {
                        Label("导出", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: SkinMetrics.fsLabel))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appearanceStore.palette.ink3)

                    if let onEdit {
                        Button(action: onEdit) {
                            Label("编辑", systemImage: "arrow.up.forward.app")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: SkinMetrics.fsLabel))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appearanceStore.palette.ink3)
                    }
                }
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
