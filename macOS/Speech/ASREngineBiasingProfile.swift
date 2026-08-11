import Foundation

/// Which contextual-biasing routes can EFFECTIVELY bias an ASR result.
/// - `weakPrompt`  — a soft prompt-level hotword hint: the Whisper-multipart `prompt`, the Gemini
///   text part, or another provider-supported context field.
/// - `hardMatch`   — the post-ASR snap applied in `RoutedSpeechCaptureService.stop()` to repair
///   near-miss spellings of domain terms. Universal: it runs on every engine's transcript.
enum ASRBiasingRoute: Sendable, Hashable {
    case weakPrompt
    case hardMatch
}

/// Single source of truth (biasing-seam audit, 2026-06-20) for which biasing routes each ASR
/// engine EFFECTIVELY carries — i.e. actually changes the inserted transcript, not merely wired.
///
/// Facts this pins so they can't be silently regressed or misread:
/// - `hardMatch` is **universal**: `RoutedSpeechCaptureService.stop()` applies
///   `biasingSets().enforce()` to EVERY engine, so every engine carries it.
/// - The shipping default engine `.cloudQwenASRFlashRealtime` carries `weakPrompt` since it moved
///   off the OmniRealtime socket onto the 非实时 HTTP endpoint's 即时热词 field (#588).
/// - `.cloudMimo` is wired with a weak-prompt provider in `ASRTranscriptionClientFactory`, but the
///   MiMo API discards text content parts (`DirectMimoTranscriptionAPI`), so it carries **no**
///   effective `weakPrompt` — hard-match only. We pin the effective (honest) behavior, not the wiring.
///
/// The `switch` is exhaustive on purpose: a new `ASREngine` case will not compile until its routes
/// are declared here. When you change which biasing closure (`hotwordsProvider`) an engine's
/// client receives in `ASRTranscriptionClientFactory` /
/// `RoutedSpeechCaptureService`, update this map **and** `ASREngineBiasingProfileTests`.
enum ASREngineBiasingProfile {
    static func routes(for engine: ASREngine) -> Set<ASRBiasingRoute> {
        switch engine {
        // Whisper-multipart `prompt` / Gemini text-part hint genuinely reaches the request body.
        case .cloudOpenAI, .cloudGemini, .customOpenAI:
            return [.weakPrompt, .hardMatch]

        // weak-prompt provider is wired in the factory but the MiMo API discards text parts →
        // no effective request-side biasing.
        case .cloudMimo:
            return [.hardMatch]

        // 千问实时 (run-task WSS): the 词典 weak prompt is sent as 即时热词 `parameters.vocabulary` on
        // the run-task frame (QwenRunTaskASRProtocol) → weakPrompt + the universal hard-match. Note
        // the field is documented for `qwen-audio-3.0-asr-flash-streaming` only, so picking the
        // Fun-ASR-Realtime model in the card drops this engine back to hard-match for that session.
        case .cloudQwenASRFlashRealtime:
            return [.weakPrompt, .hardMatch]

        // 大模型流式: hotwords are sent via the request's `corpus.context` biasing channel
        // (VolcengineRealtimeTranscriptionAPI) → carries weakPrompt + the universal hard-match.
        case .cloudVolcengineRealtime:
            return [.weakPrompt, .hardMatch]

        // In-process Qwen3-ASR (LLM decoder) takes the documented model-config `hotwords` field
        // (sherpa-onnx ≥v1.12.35; we ship v1.13.2), fed weakPrompt at recognizer build — wired
        // 2026-06-20 (#500 S1) in `RoutedSpeechCaptureService`. So it carries weakPrompt (the ONE
        // offline soft route) + the universal hard-match. SenseVoice (CTC) / FireRedASR2 / FunASR-Nano
        // expose no effective request-side biasing here, so they stay hard-match only.
        case .qwen3LocalASR:
            return [.weakPrompt, .hardMatch]

        // No request-side biasing API is used; the universal post-ASR hard-match still applies.
        case .apple, .sensevoiceLocal, .fireRedASR2AEDLocal, .funAsrNanoLocal:
            return [.hardMatch]
        }
    }
}
