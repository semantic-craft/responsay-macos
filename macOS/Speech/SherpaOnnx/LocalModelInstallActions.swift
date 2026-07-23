import Foundation

@MainActor
enum LocalModelInstallActions {
    static func onInstalled(_ spec: LocalModelSpec) {
        switch spec.capability {
        case .asr:
            ASRResidencyPrewarm.onSelection(ASREngine.selected.rawValue)
        case .ocr:
            PaddleOCRResidencyPrewarm.onSelection(OCREngine.selected.rawValue)
        default:
            break
        }
    }

    static func beforeDelete(_ spec: LocalModelSpec) {
        LocalEngineResidency.shared.unload(spec.id)
    }
}
