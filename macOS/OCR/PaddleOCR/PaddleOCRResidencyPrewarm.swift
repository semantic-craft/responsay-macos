import Foundation

@MainActor
enum PaddleOCRResidencyPrewarm {
    static func ensureRegistered() {
        PaddleOCRResidentEngine.shared.registerIfNeeded()
    }

    static func onSelection(_ raw: String, residency: LocalEngineResidency = .shared) {
        if residency === LocalEngineResidency.shared { ensureRegistered() }
        let targetID = residencyID(for: raw)
        if let targetID, residency.canControl(targetID) {
            residency.preloadInBackground(targetID)
        } else {
            let localID = LocalModelRegistry.defaultOCR.id
            if residency.isResident(localID) { residency.unload(localID) }
        }
    }

    static func residencyID(for raw: String) -> String? {
        switch OCREngine(rawValue: raw) {
        case .paddleOCRLocal: LocalModelRegistry.defaultOCR.id
        default: nil
        }
    }
}
