import Foundation
import ResponsayCore

/// The image-recognition (OCR) engine the user picks in Settings › 图片识别. Mirrors `ASREngine`:
/// the raw value is persisted under `@AppStorage("ocrEngine")` and `RoutedOCRProvider` reads
/// `selected` at snap time. Apple Vision (on-device) is the default; Mistral / 百度 are BYOK-direct
/// cloud engines (the app calls them directly — no backend in the loop). The raw values match the
/// concrete providers' `engineID`/`id`, asserted by `OCREngineTests.rawValuesMatchProviderIDs`.
enum OCREngine: String, CaseIterable, Identifiable {
    case appleVision = "apple-vision"
    case paddleOCRLocal = "local-paddleocr-v6-small"
    case mistral = "mistral-ocr"
    case baidu = "baidu-ocr"

    var id: String { rawValue }

    static let defaultsKey = "ocrEngine"

    /// Engines offered in the picker (currently all of them).
    static var selectableCases: [OCREngine] { [.appleVision, .paddleOCRLocal, .mistral, .baidu] }

    static var selected: OCREngine { selected(defaults: .standard) }

    /// Unknown / nil raw values fall back to the on-device default (never nil).
    static func selected(defaults: UserDefaults) -> OCREngine {
        guard let raw = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let engine = OCREngine(rawValue: raw) else { return .appleVision }
        return engine
    }

    var title: String {
        switch self {
        case .appleVision: "Apple Vision（本机）"
        case .paddleOCRLocal: "PaddleOCR v6 Small（本机）"
        case .mistral: "Mistral OCR（云端）"
        case .baidu: "百度 OCR（云端）"
        }
    }

    /// On-device engine: no key, no network, screenshot never leaves the Mac.
    var isLocal: Bool { self == .appleVision || self == .paddleOCRLocal }

    /// Shown in the main-window "模型选择" detail line (OCR engines have no editable model id).
    var modelLabel: String {
        switch self {
        case .appleVision: "Apple Vision"
        case .paddleOCRLocal: LocalModelRegistry.defaultOCR.id
        case .mistral: "mistral-ocr-latest"
        case .baidu: "general_basic"
        }
    }
}

/// Keychain account strings for the cloud OCR engines' BYOK secrets. Same `byok.<provider>.<field>`
/// scheme the rest of the app uses (see `CapabilityCredentialAccount.appIdAccount`). Stored via
/// `BYOKKeychain`; never in UserDefaults or logs.
enum OCRCredentialAccount {
    static let mistralAPIKey = "byok.mistral-ocr.apiKey"
    static let baiduAPIKey = "byok.baidu-ocr.apiKey"
    static let baiduSecretKey = "byok.baidu-ocr.secretKey"
}
