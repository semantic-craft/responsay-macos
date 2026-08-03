import Foundation

enum QwenASRStreamingMode: String, CaseIterable {
    case quick = "quick"
    case longForm = "long-form"

    var title: String {
        switch self {
        case .quick: "快速听写"
        case .longForm: "长篇听写"
        }
    }
}

enum QwenASRStreamingModeSettings {
    static let key = "asr.qwen.streamingMode"

    static func mode(defaults: UserDefaults = .standard) -> QwenASRStreamingMode {
        guard let raw = defaults.string(forKey: key),
              let mode = QwenASRStreamingMode(rawValue: raw) else { return .quick }
        return mode
    }

    static func select(_ mode: QwenASRStreamingMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
