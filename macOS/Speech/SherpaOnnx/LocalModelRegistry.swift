import Foundation

/// Catalog of local models, mirroring openless's `sherpa.rs` MODELS table.
/// Every entry is downloadable in-app and has a runnable engine; catalog-preview
/// placeholders without a recognizer (Paraformer, Whisper) were removed.
enum LocalModelRegistry {
    static let all: [LocalModelSpec] = [
        .senseVoiceSmall, .qwen3ASR, .funAsrNano, .kokoroMultiLangV1_1, .ctTransformerPunctZhEn,
        .paddleOCRv6Small,
    ]

    static var asrModels: [LocalModelSpec] {
        all.filter { $0.capability == .asr }
    }

    /// On-device punctuation model (`如实输入` adds punctuation offline, no LLM).
    static var punctuationModel: LocalModelSpec { .ctTransformerPunctZhEn }

    /// On-device TTS voice models (engine `TTSEngine.sherpaKokoroLocal`).
    static var ttsModels: [LocalModelSpec] {
        all.filter { $0.capability == .tts }
    }

    /// On-device OCR models used by Snap & Translate.
    static var ocrModels: [LocalModelSpec] {
        all.filter { $0.capability == .ocr }
    }

    static var downloadable: [LocalModelSpec] {
        all.filter(\.isDownloadable)
    }

    static func spec(id: String) -> LocalModelSpec? {
        all.first { $0.id == id }
    }

    /// The default offline ASR model (engine `ASREngine.sensevoiceLocal`).
    static var defaultASR: LocalModelSpec { .senseVoiceSmall }

    /// The default on-device TTS model (engine `TTSEngine.sherpaKokoroLocal`).
    static var defaultTTS: LocalModelSpec { .kokoroMultiLangV1_1 }

    /// The default on-device OCR model (engine `OCREngine.paddleOCRLocal`).
    static var defaultOCR: LocalModelSpec { .paddleOCRv6Small }
}

extension LocalModelSpec {
    /// SenseVoice-Small int8 (zh/en/ja/ko/yue), sherpa-onnx GitHub release.
    /// Verified via `gh api .../releases/tags/asr-models` (size + sha256 digest).
    static let senseVoiceSmall = LocalModelSpec(
        id: ASREngine.sensevoiceLocal.rawValue,
        displayName: "SenseVoice Small（中/粤/英/日/韩）",
        capability: .asr,
        runtime: .sherpaOnnx,
        family: .senseVoice,
        languages: ["zh", "en", "ja", "ko", "yue"],
        qualityTier: "balanced",
        directoryName: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09",
        expected: ExpectedMetrics(asrRealtimeFactor: 8.0, approxDiskBytes: 240_000_000),
        download: DownloadSource(
            urls: [
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2")!,
                // China-friendly GitHub release proxies (two independent ones so a
                // single proxy outage doesn't strand 国内 users); sha256 is verified
                // regardless of source.
                URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2")!,
                URL(string: "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2")!,
            ],
            sha256: "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63",
            byteSize: 165_783_878,
            requiredFiles: ["model.int8.onnx", "tokens.txt"]
        )
    )

    /// Fun-ASR Nano (fp16) — Alibaba Tongyi FunAudioLLM's latest industrial ASR,
    /// LLM-based (encoder-adaptor → Qwen3-0.6B decoder) with 7 major Chinese dialects
    /// + 26 regional accents. fp16 default (encoder/embedding int8 + llm fp16); an
    /// int8 variant exists as a smaller alternative.
    /// sha256 from `gh api .../releases/tags/asr-models`.
    static let funAsrNano = LocalModelSpec(
        id: ASREngine.funAsrNanoLocal.rawValue,
        displayName: "Fun-ASR Nano（阿里·中文方言广）",
        capability: .asr,
        runtime: .sherpaOnnx,
        family: .funAsrNano,
        languages: ["zh", "en", "yue", "dialect", "multi"],
        qualityTier: "chinese-dialect-broad",
        directoryName: "sherpa-onnx-funasr-nano-fp16-2025-12-30",
        expected: ExpectedMetrics(asrRealtimeFactor: 1.5, approxDiskBytes: 1_550_000_000),
        download: DownloadSource(
            urls: [
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-fp16-2025-12-30.tar.bz2")!,
                URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-fp16-2025-12-30.tar.bz2")!,
                URL(string: "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-fp16-2025-12-30.tar.bz2")!,
            ],
            sha256: "a07a996361aa2f8b2c4f47861fe01953b5509664efa3392b734580b1eeb362e3",
            byteSize: 1_030_076_153,
            requiredFiles: [
                "encoder_adaptor.int8.onnx", "llm.fp16.onnx", "embedding.int8.onnx",
                "Qwen3-0.6B/tokenizer.json",
            ]
        )
    )

    /// Qwen3-ASR 0.6B int8 — multilingual + Chinese/dialect + code-switching,
    /// runs in the same sherpa-onnx offline path and is the recommended local default.
    /// sha256 from `gh api .../releases/tags/asr-models`.
    static let qwen3ASR = LocalModelSpec(
        id: ASREngine.qwen3LocalASR.rawValue,
        displayName: "Qwen3-ASR 0.6B（多语·中文方言强）",
        capability: .asr,
        runtime: .sherpaOnnx,
        family: .qwen3Asr,
        languages: ["zh", "en", "yue", "multi"],
        qualityTier: "chinese-strong",
        directoryName: "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25",
        expected: ExpectedMetrics(asrRealtimeFactor: 3.0, approxDiskBytes: 900_000_000),
        download: DownloadSource(
            urls: [
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2")!,
                URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2")!,
                URL(string: "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2")!,
            ],
            sha256: "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96",
            byteSize: 878_702_423,
            requiredFiles: [
                "conv_frontend.onnx", "encoder.int8.onnx", "decoder.int8.onnx",
                "tokenizer/vocab.json",
            ]
        )
    )

    /// Kokoro multi-lang v1.1 (zh + en, 103 voices) — on-device natural TTS, full
    /// fp32 for best naturalness (the product's signature feature; int8 trades
    /// naturalness for size and was rejected as default). Engine
    /// `TTSEngine.sherpaKokoroLocal` (id "local-kokoro"). sherpa-onnx tts-models
    /// release; sha256 + size verified by downloading + `shasum`/`tar` (the release
    /// API exposes no digest), file layout confirmed by inspecting the archive.
    static let kokoroMultiLangV1_1 = LocalModelSpec(
        id: "local-kokoro",
        displayName: "Kokoro 多语音色（中/英，自然朗读）",
        capability: .tts,
        runtime: .sherpaOnnx,
        family: .kokoro,
        languages: ["zh", "en"],
        qualityTier: "natural",
        directoryName: "kokoro-multi-lang-v1_1",
        expected: ExpectedMetrics(asrRealtimeFactor: nil, approxDiskBytes: 370_000_000),
        download: DownloadSource(
            urls: [
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2")!,
                URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2")!,
                URL(string: "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2")!,
            ],
            sha256: "a3f4c73d043860e3fd2e5b06f36795eb81de0fc8e8de6df703245edddd87dbad",
            byteSize: 364_816_464,
            requiredFiles: [
                "model.onnx", "voices.bin", "tokens.txt",
                "lexicon-us-en.txt", "lexicon-zh.txt", "espeak-ng-data/cmn_dict",
            ]
        )
    )

    /// CT-Transformer offline punctuation (zh+en), int8. Adds punctuation to the verbatim output
    /// of an offline ASR model in the 如实输入 path — on-device, no LLM, no network. int8 (65 MB
    /// download) is chosen over fp32 (279 MB): punctuation restoration is robust to quantization.
    /// sha256 + size + archive layout verified by downloading the asset and `shasum`/`tar`.
    static let ctTransformerPunctZhEn = LocalModelSpec(
        id: "local-punct-ct-transformer-zh-en",
        displayName: "中英标点模型（如实听写离线加标点）",
        capability: .punctuation,
        runtime: .sherpaOnnx,
        family: .ctTransformerPunct,
        languages: ["zh", "en"],
        qualityTier: "punctuation",
        directoryName: "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8",
        expected: ExpectedMetrics(asrRealtimeFactor: nil, approxDiskBytes: 76_000_000),
        download: DownloadSource(
            urls: [
                URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2")!,
                URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2")!,
                URL(string: "https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2")!,
            ],
            sha256: "c0d5aa5f8eeb686032345e180bedf39319dc2e0556781c6264bcadba8328a6e1",
            byteSize: 64_717_756,
            requiredFiles: ["model.int8.onnx"]
        )
    )

    /// PaddleOCR PP-OCRv6 Small — local screenshot OCR (detection + recognition).
    /// Official ONNX files from PaddlePaddle Hugging Face repos; file sizes and sha256 verified
    /// by downloading on 2026-06-16. The app stores det/rec in one model directory so Snap OCR can
    /// load them atomically.
    static let paddleOCRv6Small = LocalModelSpec(
        id: "local-paddleocr-v6-small",
        displayName: "PaddleOCR v6 Small（本机截图取字）",
        capability: .ocr,
        runtime: .onnxRuntime,
        family: .paddleOCR,
        languages: ["zh", "zh-Hant", "en", "ja", "multi"],
        qualityTier: "balanced-local-ocr",
        directoryName: "paddleocr-v6-small-onnx-2026-06-11",
        expected: ExpectedMetrics(asrRealtimeFactor: nil, approxDiskBytes: 35_000_000),
        download: DownloadSource(
            urls: [],
            sha256: "ffce5ffb77649a845f8649e0572611d58ff46621245759c0ad075112a3f4d113",
            byteSize: 31_191_354,
            requiredFiles: [
                "det/inference.onnx", "det/inference.yml",
                "rec/inference.onnx", "rec/inference.yml",
            ],
            files: [
                DownloadFile(
                    relativePath: "det/inference.onnx",
                    urls: [
                        URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx")!,
                        URL(string: "https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx")!,
                        URL(string: "https://modelscope.cn/models/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/master/inference.onnx")!,
                    ],
                    sha256: "d73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e",
                    byteSize: 9_880_512),
                DownloadFile(
                    relativePath: "det/inference.yml",
                    urls: [
                        URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.yml")!,
                        URL(string: "https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.yml")!,
                        URL(string: "https://modelscope.cn/models/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/master/inference.yml")!,
                    ],
                    sha256: "193f435274bf9f0b5f71a929bbfbcf148282df7e633b34e7c373e8f44741b516",
                    byteSize: 885),
                DownloadFile(
                    relativePath: "rec/inference.onnx",
                    urls: [
                        URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx")!,
                        URL(string: "https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx")!,
                        URL(string: "https://modelscope.cn/models/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/master/inference.onnx")!,
                    ],
                    sha256: "5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634",
                    byteSize: 21_159_378),
                DownloadFile(
                    relativePath: "rec/inference.yml",
                    urls: [
                        URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.yml")!,
                        URL(string: "https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.yml")!,
                        URL(string: "https://modelscope.cn/models/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/master/inference.yml")!,
                    ],
                    sha256: "ab078671bb49f06228eadccd34f1bb501e157f7a047095ffb943ba81512c77d1",
                    byteSize: 150_579),
            ]
        )
    )

}
