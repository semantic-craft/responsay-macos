import SwiftUI

struct SettingsLocalModelCard: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let capability: LocalModelCapability
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let modelManagers: [LocalModelDownloadManager]
    let residency: LocalEngineResidency
    @Binding var residencyError: String?

    var body: some View {
        let managers = modelManagers.filter { $0.spec.capability == capability }
        if !managers.isEmpty {
            WarmCard {
                CapabilityHeader(systemImage: "cpu", title: title, subtitle: subtitle)
                ForEach(Array(managers.enumerated()), id: \.element.id) { idx, manager in
                    if idx > 0 { WarmDivider() }
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(appearanceStore.palette.ink)
                            Text("\(manager.sizeText) · 原生支持，零配置")
                                .font(.system(size: 12))
                                .foregroundStyle(appearanceStore.palette.ink3)
                            if let info = manager.spec.offlineModelInfo {
                                Text(info.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(appearanceStore.palette.ink3)
                                Text("出品方：\(info.vendor)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(appearanceStore.palette.ink3)
                                ForEach(info.highlights, id: \.self) { highlight in
                                    Text("· 厂商称：\(highlight)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(appearanceStore.palette.ink3)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 6) {
                            SettingsModelControls(manager: manager)
                            SettingsResidencyControls(
                                manager: manager,
                                residency: residency,
                                residencyError: $residencyError)
                        }
                    }
                }
                if let residencyError {
                    Text(residencyError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}
