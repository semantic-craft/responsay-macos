import Foundation

enum ASREngine: String, CaseIterable {
    case apple = "apple"
    case cloudOpenAI = "cloud-openai"
    case cloudMimo = "cloud-mimo"
    /// Google Gemini batch ASR (整段识别) via native :generateContent (BYOK-direct).
    case cloudGemini = "cloud-gemini"
    /// In-process offline ASR via sherpa-onnx + SenseVoice (no backend, no Python).
    case sensevoiceLocal = "offline-sensevoice"
    /// In-process offline ASR via sherpa-onnx + Qwen3-ASR (multilingual, in-process).
    case qwen3LocalASR = "offline-qwen3-asr"
    /// In-process offline ASR via sherpa-onnx + Fun-ASR Nano (Alibaba Tongyi, LLM-based, broad dialect coverage).
    case funAsrNanoLocal = "offline-funasr-nano"
    /// 阿里云百炼 实时语音识别 (Qwen-Audio-3.0-ASR-Flash-Streaming / Fun-ASR-Realtime) over the
    /// DashScope **run-task** WebSocket: frames stream while the hotkey is held, `finish-task` on
    /// release returns the 整段 transcript. 词典 hotwords ride the run-task 即时热词 `vocabulary` field.
    ///
    /// Final-only: streaming buys latency (the audio is recognised by the time the key comes up),
    /// not a live capsule preview. Replaced the OmniRealtime engine (#588), which spoke a different
    /// protocol on the sibling `/api-ws/v1/realtime` path and whose only model supports no hotwords.
    case cloudQwenASRFlashRealtime = "cloud-qwen-asr-flash-realtime"
    /// 火山引擎大模型流式语音识别 (流式输入模式, `bigmodel_nostream`, #580): record locally, then on
    /// stop replay the clip over the streaming WebSocket for one clean final — lower
    /// stop-to-final latency than the submit/query 录音文件 path. Shares the 火山
    /// (`volcengine-flash`) key. Final-only for now; live typewriter preview is a follow-up.
    case cloudVolcengineRealtime = "cloud-volcengine-realtime"
    /// User-supplied OpenAI-Whisper-compatible endpoint (BYOK — ADR-0023).
    case customOpenAI = "custom-openai"

    static let defaultsKey = "asrEngine"

    /// Engines offered in Settings. Fast final-only cloud paths stay grouped
    /// first, followed by other cloud providers and local/offline engines.
    static var selectableCases: [ASREngine] {
        [
            .cloudQwenASRFlashRealtime,
            .cloudVolcengineRealtime,
            .cloudMimo,
            .cloudOpenAI,
            .cloudGemini,
            .customOpenAI,
            .apple,
            .sensevoiceLocal,
            .qwen3LocalASR,
            .funAsrNanoLocal,
        ]
    }

    static var selected: ASREngine {
        selected(defaults: .standard)
    }

    static func selected(defaults: UserDefaults) -> ASREngine {
        if let engine = fromStoredValue(defaults.string(forKey: defaultsKey)) {
            return engine
        }
        // Cold-start default = 千问实时 (run-task WSS; was the OmniRealtime socket until #588).
        // When no Qwen key is configured, the router transcribes via Apple without mutating this
        // selection (#389), so fresh installs aren't broken.
        return .cloudQwenASRFlashRealtime
    }

    /// Resolves a persisted supported engine identifier.
    static func fromStoredValue(_ raw: String?) -> ASREngine? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return ASREngine(rawValue: trimmed)
    }

    var title: String {
        switch self {
        case .apple: "Apple 系统原生"
        case .cloudOpenAI: "OpenAI"
        case .cloudMimo: "小米Mimo"
        case .cloudGemini: "Google Gemini"
        case .cloudQwenASRFlashRealtime: "阿里云百炼 · 千问实时"
        case .cloudVolcengineRealtime: "火山引擎 · 豆包流式"
        case .sensevoiceLocal: "SenseVoice"
        case .qwen3LocalASR: "Qwen3-ASR"
        case .funAsrNanoLocal: "Fun-ASR Nano"
        case .customOpenAI: "自定义 OpenAI 兼容"
        }
    }

    /// Offline whole-utterance AED models that emit NO punctuation themselves, so the 如实输入
    /// path may restore it on-device (CT-Transformer). Apple and the streaming Zipformer already
    /// punctuate; cloud engines punctuate server-side — none of those should be re-punctuated.
    var lacksNativePunctuation: Bool {
        switch self {
        case .sensevoiceLocal, .qwen3LocalASR:
            return true
        default:
            return false
        }
    }

    /// The corresponding provider ID in `ProviderCatalog` for BYOK settings.
    var associatedProviderId: String? {
        switch self {
        case .cloudOpenAI: return "openai"
        case .cloudMimo: return "mimo"
        case .cloudGemini: return "gemini"
        case .cloudQwenASRFlashRealtime: return "qwen-asr-flash"
        case .cloudVolcengineRealtime: return "volcengine-flash"
        case .customOpenAI: return "custom"
        case .apple, .sensevoiceLocal, .qwen3LocalASR, .funAsrNanoLocal:
            return nil
        }
    }

    /// Downloaded model required by this engine, or nil for Apple and cloud choices.
    var localModelSpec: LocalModelSpec? {
        switch self {
        case .sensevoiceLocal: .senseVoiceSmall
        case .qwen3LocalASR: .qwen3ASR
        case .funAsrNanoLocal: .funAsrNano
        case .apple, .cloudOpenAI, .cloudMimo, .cloudGemini,
                .cloudQwenASRFlashRealtime, .cloudVolcengineRealtime, .customOpenAI:
            nil
        }
    }
}
