import Foundation
import OSLog
import ResponsayCore

/// On-device TTS via the embedded sherpa-onnx `OfflineTts` running Kokoro
/// (issue 202). Native, offline, in-process — no backend, no Python. The mirror
/// image of `SenseVoiceRecognizer` on the ASR side, and conforms to the pure
/// `SpeechSynthesizer` boundary (201) so the read-aloud pipeline (194) never knows
/// which engine speaks.
///
/// Kokoro ONNX exposes no native word/token alignment, so `providerTiming` is
/// always `nil`; per-word timing is approximated downstream by the proportional
/// `WordTimingAligner` (135). Config matches the official sherpa-onnx Swift TTS
/// example + the kokoro-multi-lang CLI: model/voices/tokens + espeak-ng-data +
/// the us-en/zh lexicons + the zh rule FSTs (date/number/phone) + the jieba dict.
///
/// `@unchecked Sendable`: the underlying `OfflineTts` is only ever used
/// sequentially (one `generate` at a time), so the cached instance is safe to hold
/// and synthesize from a background task.
final class SherpaTTSEngine: SpeechSynthesizer, @unchecked Sendable {
    /// File / folder names inside a Kokoro multi-lang model directory.
    enum File {
        static let model = "model.onnx"
        static let voices = "voices.bin"
        static let tokens = "tokens.txt"
        static let espeakData = "espeak-ng-data"
        static let dict = "dict"
        static let lexiconEn = "lexicon-us-en.txt"
        static let lexiconZh = "lexicon-zh.txt"
        /// zh number/date/phone normalization rule FSTs (improve Chinese reading).
        static let ruleFsts = ["date-zh.fst", "number-zh.fst", "phone-zh.fst"]
    }

    private let tts: SherpaOnnxOfflineTtsWrapper
    /// Speaker id into Kokoro's voice bank (v1.1-zh ships 103 voices).
    private let sid: Int
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "KokoroTTS")

    /// - Parameters:
    ///   - modelDir: directory holding the Kokoro files (a `LocalModelSpec.storagePath`).
    ///   - sid: speaker id; 0 is a safe default.
    /// - Throws: `TTSError.modelNotInstalled` if a required file is missing.
    init(modelDir: URL, sid: Int = 0) throws {
        let required = [File.model, File.voices, File.tokens]
        for name in required where !FileManager.default.fileExists(
            atPath: modelDir.appendingPathComponent(name).path) {
            throw TTSError.modelNotInstalled
        }
        func path(_ name: String) -> String { modelDir.appendingPathComponent(name).path }

        // espeak-ng-data + jieba dict are optional on disk; pass only if present so a
        // partial install degrades to a clear error at generate time, not a bad path.
        let fm = FileManager.default
        let dataDir = fm.fileExists(atPath: path(File.espeakData)) ? path(File.espeakData) : ""
        let dictDir = fm.fileExists(atPath: path(File.dict)) ? path(File.dict) : ""
        let lexicon = [File.lexiconEn, File.lexiconZh]
            .filter { fm.fileExists(atPath: path($0)) }
            .map(path)
            .joined(separator: ",")
        let ruleFsts = File.ruleFsts
            .filter { fm.fileExists(atPath: path($0)) }
            .map(path)
            .joined(separator: ",")

        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: path(File.model),
            voices: path(File.voices),
            tokens: path(File.tokens),
            dataDir: dataDir,
            dictDir: dictDir,
            lexicon: lexicon
        )
        let model = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: 2)
        var config = sherpaOnnxOfflineTtsConfig(model: model, ruleFsts: ruleFsts)
        tts = SherpaOnnxOfflineTtsWrapper(config: &config)
        self.sid = sid
        Self.log.info("Kokoro TTS loaded from \(modelDir.lastPathComponent, privacy: .public)")
    }

    /// Synthesize `text` to mono PCM at `speed` (1.0 = natural; clamped to [0.5, 2.0]).
    /// Kokoro applies the rate at synthesis (pitch preserved), so the produced duration
    /// reflects it and the proportional timeline stays in sync (issue 198). Blocking CPU
    /// work — call off the main thread. Empty text → `TTSError.emptyText`.
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }
        let rate = Float(Self.clampSpeed(speed))
        let audio = tts.generate(text: trimmed, sid: sid, speed: rate)
        let samples = audio.samples
        guard !samples.isEmpty else {
            throw TTSError.providerReturnedNoAudio(provider: "Kokoro")
        }
        return SynthesizedSpeech(
            samples: samples,
            sampleRate: Int(audio.sampleRate),
            providerTiming: nil   // Kokoro ONNX has no native word alignment
        )
    }
}

extension SherpaTTSEngine {
    /// Load the engine for the installed default Kokoro model, or throw
    /// `TTSError.modelNotInstalled` if it isn't downloaded yet. Speaking rate is passed
    /// per `synthesize(_:speed:)` call, not fixed here (issue 198).
    static func loadDefault(sid: Int = 0) throws -> SherpaTTSEngine {
        try SherpaTTSEngine(modelDir: LocalModelRegistry.defaultTTS.storagePath, sid: sid)
    }
}
