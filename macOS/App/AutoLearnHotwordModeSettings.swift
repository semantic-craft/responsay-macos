import Foundation

enum AutoLearnHotwordMode: String, CaseIterable {
    case localRules = "local-rules"
    case localModel = "local-model"

    var title: String {
        switch self {
        case .localRules: return "本机规则"
        case .localModel: return "本地模型"
        }
    }

    var privacySummary: String {
        switch self {
        case .localRules:
            return "只看你刚写入和刚修改的片段，不调用模型，不离开本机。"
        case .localModel:
            return "把纠错片段发给本机 OpenAI-compatible 运行器；内容不上传云端。"
        }
    }
}

enum AutoLearnHotwordModeSettings {
    static let key = "hotword.autoLearn.mode"

    static func mode(defaults: UserDefaults = .standard) -> AutoLearnHotwordMode {
        guard let raw = defaults.string(forKey: key),
              let mode = AutoLearnHotwordMode(rawValue: raw) else {
            return .localRules
        }
        return mode
    }

    static func select(_ mode: AutoLearnHotwordMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
