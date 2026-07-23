import Foundation

/// User-facing metadata for the offline model list: a one-line summary, the vendor,
/// and the vendor's advertised highlights (rendered as vendor claims — 「厂商称…」).
/// Describes an offline speech model shown in the model picker.
struct OfflineModelInfo: Equatable, Sendable {
    /// 出品方.
    let vendor: String
    /// 一句话简介（这是什么、适合谁）.
    let summary: String
    /// 厂商标榜的亮点（以「厂商称…」语气呈现，非我们自测）.
    let highlights: [String]
}

extension OfflineModelInfo {
    /// Metadata keyed by the ASR engine raw value — which equals `LocalModelSpec.id`
    /// for downloadable models, and "apple" for the zero-download system engine.
    /// Returns nil for cloud engines (their metadata lives in the provider catalog).
    static func forEngineRawValue(_ raw: String) -> OfflineModelInfo? {
        switch raw {
        case ASREngine.fireRedASR2AEDLocal.rawValue:
            return OfflineModelInfo(
                vendor: "小红书 FireRed 团队",
                summary: "开源工业级中文 ASR，整段识别，方言强项。",
                highlights: [
                    "普通话 + 中文方言 + 英语",
                    "FireRedASR2 较 v1 识别精度更高、方言与口音覆盖更广",
                    "开源工业级模型",
                ])
        case ASREngine.funAsrNanoLocal.rawValue:
            return OfflineModelInfo(
                vendor: "阿里巴巴通义实验室 FunAudioLLM",
                summary: "阿里最新工业级 ASR 的轻量档，整段识别。",
                highlights: [
                    "覆盖 7 大中文方言（吴 / 粤 / 闽 / 客 / 赣 / 湘 / 晋）+ 26 种地方口音",
                    "支持 30 语种",
                    "工业级，可做企业定制",
                ])
        case ASREngine.qwen3LocalASR.rawValue:
            return OfflineModelInfo(
                vendor: "阿里巴巴通义千问",
                summary: "紧凑高效的多语 ASR，整段识别，快档。",
                highlights: [
                    "语言识别 + 语音识别一体",
                    "官方称支持 30 语种 + 22 种中文方言",
                    "0.6B 为精度-效率平衡档",
                ])
        case ASREngine.sensevoiceLocal.rawValue:
            return OfflineModelInfo(
                vendor: "阿里巴巴通义实验室 FunAudioLLM",
                summary: "多语高精度 ASR，非自回归、低延迟，快档。",
                highlights: [
                    "高精度多语（50+ 语种）",
                    "含语音情感识别 + 音频事件检测",
                    "官方称中文 / 粤语较 Whisper 准约 50%、推理快约 15×",
                ])
        case ASREngine.apple.rawValue:
            return OfflineModelInfo(
                vendor: "Apple",
                summary: "macOS 系统自带语音识别，零下载。",
                highlights: [
                    "系统原生、零下载",
                    "本机隐私（on-device）",
                    "SpeechAnalyzer / SFSpeechRecognizer",
                ])
        case "local-punct-ct-transformer-zh-en":
            // 不是我们改的模型：直接用 sherpa-onnx 预编译的 CT-Transformer 标点模型；
            // 底层是 FunASR / 阿里达摩院的 punc_ct-transformer，跑在跟 SenseVoice/Kokoro 同一套框架上。
            return OfflineModelInfo(
                vendor: "sherpa-onnx（k2-fsa）打包 · 底层 FunASR / 阿里达摩院 CT-Transformer",
                summary: "给离线「如实」听写补中英标点——纯本机、零联网、零 LLM。",
                highlights: [
                    "CT-Transformer 标点恢复模型（punc_ct-transformer）",
                    "int8 量化 ~65MB，标点恢复对量化不敏感",
                    "与 SenseVoice / Kokoro 同一套 sherpa-onnx 原生框架",
                ])
        case "local-paddleocr-v6-small":
            return OfflineModelInfo(
                vendor: "PaddlePaddle / PaddleOCR",
                summary: "PP-OCRv6 Small 本机截图取字，下载约 31MB，适合网页、PDF 与普通截图。",
                highlights: [
                    "det + rec 双 ONNX 模型，截图不离开这台 Mac",
                    "官方称 PP-OCRv6 单模型覆盖中英日与多种拉丁语系文字",
                    "Small 档平衡体积与准确率，作为 Responsay 本机 OCR 默认候选",
                ])
        default:
            return nil
        }
    }
}

extension ASREngine {
    /// Vendor / summary / highlights for the offline model list. Nil for cloud engines.
    var offlineModelInfo: OfflineModelInfo? { OfflineModelInfo.forEngineRawValue(rawValue) }
}

extension LocalModelSpec {
    /// Vendor / summary / highlights for the offline model list (downloadable models).
    /// Nil for models without curated metadata (e.g. Kokoro TTS, the punctuation model).
    var offlineModelInfo: OfflineModelInfo? { OfflineModelInfo.forEngineRawValue(id) }
}
