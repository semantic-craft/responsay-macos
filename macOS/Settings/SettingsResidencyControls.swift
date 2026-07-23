import SwiftUI

struct SettingsResidencyControls: View {
    let manager: LocalModelDownloadManager
    let residency: LocalEngineResidency
    @Binding var residencyError: String?

    var body: some View {
        let id = manager.spec.id
        if residency.canControl(id), manager.state == .installed {
            let resident = residency.isResident(id)
            HStack(spacing: 8) {
                MemChip(resident: resident)
                if resident {
                    Button("从内存卸载") { residency.unload(id) }
                        .disabled(residency.isCapturing(id))
                } else {
                    Button("加载到内存") {
                        residencyError = nil
                        do { try residency.preload(id) }
                        catch { residencyError = "加载失败：\(error.localizedDescription)" }
                    }
                }
            }
            .controlSize(.small)
        }
    }
}
