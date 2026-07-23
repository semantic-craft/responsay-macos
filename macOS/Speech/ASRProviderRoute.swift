import Foundation

/// One ASR route decision shared by dictation and practice transcription.
enum ASRProviderRoute: Equatable {
    case apple
    case openAI
    case mimo
    case gemini
    case qwenASRFlashRealtime
    case volcengineFlash
    case volcengineRealtime
    case sensevoiceLocal
    case qwen3LocalASR
    case fireRedASR2AEDLocal
    case funAsrNanoLocal
    case customOpenAI

    static func dictation(
        selected: ASREngine = ASREngine.selected,
        isInstalled: (LocalModelSpec) -> Bool = { $0.isInstalled },
        cloudHasKey: (ASREngine) -> Bool = { ModelLaneReadinessResolver().asr(optionId: $0.rawValue).isReady }
    ) -> ASRProviderRoute {
        from(engine: ASRFallback.effectiveEngine(
            selected,
            isInstalled: isInstalled,
            cloudHasKey: cloudHasKey))
    }

    static func from(engine: ASREngine) -> ASRProviderRoute {
        switch engine {
        case .apple:
            return .apple
        case .cloudOpenAI:
            return .openAI
        case .cloudMimo:
            return .mimo
        case .cloudGemini:
            return .gemini
        case .cloudQwenASRFlashRealtime:
            return .qwenASRFlashRealtime
        case .cloudVolcengineFlash:
            return .volcengineFlash
        case .cloudVolcengineRealtime:
            return .volcengineRealtime
        case .sensevoiceLocal:
            return .sensevoiceLocal
        case .qwen3LocalASR:
            return .qwen3LocalASR
        case .fireRedASR2AEDLocal:
            return .fireRedASR2AEDLocal
        case .funAsrNanoLocal:
            return .funAsrNanoLocal
        case .customOpenAI:
            return .customOpenAI
        }
    }

    static func from(providerID: String?) -> ASRProviderRoute? {
        guard let id = ASRModelSelection.canonicalProviderId(providerID) else { return nil }
        switch id {
        case "qwen-asr-flash":
            return .qwenASRFlashRealtime
        case "volcengine-flash":
            return .volcengineFlash
        case "openai":
            return .openAI
        case "mimo":
            return .mimo
        case "gemini":
            return .gemini
        case "custom":
            return .customOpenAI
        default:
            return nil
        }
    }

    var cloudEngine: ASREngine? {
        switch self {
        case .qwenASRFlashRealtime:
            return .cloudQwenASRFlashRealtime
        case .volcengineFlash:
            return .cloudVolcengineFlash
        case .volcengineRealtime:
            return .cloudVolcengineRealtime
        case .openAI:
            return .cloudOpenAI
        case .mimo:
            return .cloudMimo
        case .gemini:
            return .cloudGemini
        case .customOpenAI:
            return .customOpenAI
        case .apple, .sensevoiceLocal, .qwen3LocalASR, .fireRedASR2AEDLocal, .funAsrNanoLocal:
            return nil
        }
    }
}
