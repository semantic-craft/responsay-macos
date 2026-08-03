import AVFoundation
import AVFAudio
import Foundation
import OSLog
import ResponsayCore

@MainActor
public final class CloudQwenSpeechCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "cloud-asr")
    #if os(macOS)
    // 蓝牙麦克风修复: AVCaptureSession binds a specific device up front (like getUserMedia), so the
    // BT default can't poison the input format. iOS keeps AVAudioEngine (no device override there).
    private var recorder: AVCaptureAudioRecorder?
    #else
    private let engine = AVAudioEngine()
    #endif
    /// Built on first use, not in `init`: the builder reads the BYOK key from the Keychain,
    /// and this service is constructed at app launch (stored property chain via
    /// RoutedSpeechCaptureService → CaptureController → AppBootstrap). An eager build did
    /// one blocking securityd round-trip per cloud service on the main thread before the
    /// first frame — and hung the ResponsayMacTests host forever on the Keychain ACL prompt,
    /// since the freshly built test binary is never on the item's ACL. `start()` rebuilds
    /// before every capture anyway, so the init-time client was never used.
    private lazy var client: any TranscriptionAPI = clientBuilder({ [profileStore] in profileStore.profile })
    /// Rebuilt per capture (see `start`). The transcription client captures its Base URL by
    /// value at build time, so a long-lived service would otherwise keep calling the host it
    /// was first built with — e.g. still hitting the Token Plan host after the user switched
    /// to 按量付费, sending the new sk- key to the wrong host → 401.
    private let clientBuilder: (@escaping @Sendable () -> SpeechCaptureProfile) -> any TranscriptionAPI
    private let providerName: String
    private let profileStore: SpeechCaptureProfileStore
    private let requireMicPermission: () throws -> Void
    private var recording: CloudASRRecordingSession?
    private var activeLocale: CaptureLocale = .chinese

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }
    private var partialContinuation: AsyncStream<String>.Continuation?

    /// Cloud multimodal batch: it injects the weak biasing hint as text, so a near-empty clip can echo
    /// the list back → `needsEchoFilter`. Volcengine variants are final-only; the rest may trickle
    /// cosmetic post-upload SSE partials.
    public var captureCapability: SpeechCaptureCapability {
        .init(partialStyle: providerName.hasPrefix("volcengine") ? .none : .postUploadSSE,
              needsEchoFilter: true)
    }

    /// Minimum peak input level (0...1, same scale as `levels`) that counts as speech.
    /// Real speech peaks well above this; a silent room or muted mic stays below it.
    /// Conservatively low to avoid dropping genuinely quiet speech; tune on a real Mac.
    private static let speechLevelThreshold: Float = 0.02

    /// Minimum capture length that can plausibly be speech. A rapid double-tap of the
    /// hotkey records a ~20 ms clip whose keystroke transient can spike the peak past the
    /// silence gate above; gating on duration too stops that near-empty clip from reaching a
    /// multimodal ASR that would answer it by echoing its own biasing hint. Tune on a real Mac.
    private static let minSpeechDuration: Double = 0.35

    /// Raw-byte ceiling for a single direct transcription request (≈ 10 MB base64). The
    /// segmented path keeps every request under this; the fallback only sends the raw clip
    /// when it is already this small.
    private static let maxRequestBytes = 7_500_000

    // App-direct only: this service builds a direct cloud transcription client (BYOK).
    // The former backend-relay init was removed with its last consumer (issue 353 / 猎虫① H1),
    // completing ADR-0029 for this file.
    /// `clientBuilder` receives a live reader of this service's capture profile:
    /// the profile is set per-capture (`setCaptureProfile`) long after the client
    /// is constructed, so the client must read it through the closure. The old
    /// `init(provider:client:)` shape took a finished client whose
    /// `profileProvider` could only ever be the `.dictation` default — the
    /// faithful-profile prompt silently never fired for the externally-built
    /// OpenAI/MiMo/custom clients (猎虫① H9).
    public init(
        provider: String,
        requireMicPermission: @escaping () throws -> Void,
        clientBuilder: @escaping (_ profile: @escaping @Sendable () -> SpeechCaptureProfile) -> any TranscriptionAPI
    ) {
        let store = SpeechCaptureProfileStore()
        self.profileStore = store
        self.providerName = provider
        self.requireMicPermission = requireMicPermission
        self.clientBuilder = clientBuilder
    }

    public func start(locale: CaptureLocale) throws {
        // Re-resolve the client from current settings so a provider/region/plan change since
        // construction (→ Base URL, model, key) takes effect without an app restart.
        client = clientBuilder({ [profileStore] in profileStore.profile })
        let profile = profileStore.profile
        log.info("Cloud ASR capture requested for \(locale.rawValue, privacy: .public) via \(self.providerName, privacy: .public); profile \(profile.rawValue, privacy: .public)")
        try requireMicPermission()
        activeLocale = locale

        let (partialStream, partialContinuation) = AsyncStream.makeStream(of: String.self)
        partialTranscripts = partialStream
        self.partialContinuation = partialContinuation
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("responsay-cloud-asr-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let (levelStream, levelContinuation) = AsyncStream.makeStream(of: Float.self)

        #if os(macOS)
        // Recorder delivers 16 kHz mono Float; the WAV is written in that format and decoded
        // back to 16 kHz mono Int16 before upload (`decodeTo16kMonoInt16`).
        let recording = try CloudASRRecordingSession(
            fileURL: fileURL,
            format: AVCaptureAudioRecorder.deliveredFormat,
            levelContinuation: levelContinuation)
        levels = levelStream
        self.recording = recording
        let recorder = AVCaptureAudioRecorder()
        self.recorder = recorder
        do {
            try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID) { @Sendable buffer in
                recording.append(buffer)
            }
        } catch {
            recording.finish()
            self.recording = nil
            self.recorder = nil
            partialContinuation.finish()
            self.partialContinuation = nil
            throw error
        }
        #else
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let recording = try CloudASRRecordingSession(
            fileURL: fileURL,
            format: format,
            levelContinuation: levelContinuation)
        levels = levelStream
        self.recording = recording

        // Idempotent: clear any tap a not-yet-finished async stop() left behind, so rapid Fn taps
        // can't hit AVAudioEngine's one-tap-per-node assertion and wedge the recorder.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            recording.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            recording.finish()
            self.recording = nil
            partialContinuation.finish()
            self.partialContinuation = nil
            throw error
        }
        #endif
        log.info("Backend ASR capture started for \(locale.rawValue, privacy: .public) via \(self.providerName, privacy: .public); profile \(profile.rawValue, privacy: .public)")
    }

    public func stop() async throws -> String {
        #if os(macOS)
        recorder?.stop()
        recorder = nil
        #else
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #endif

        defer {
            partialContinuation?.finish()
            partialContinuation = nil
        }

        guard let recording else { return "" }
        self.recording = nil
        recording.finish()

        defer { try? FileManager.default.removeItem(at: recording.fileURL) }

        // Silence gate (defense in depth): if the hotkey was pressed but nothing was
        // spoken, the captured audio never rose above the noise floor. Skip the backend
        // round-trip entirely and report no speech, so a multimodal ASR model is never
        // handed near-silent audio it could answer by echoing its own instructions.
        guard recording.durationSeconds >= Self.minSpeechDuration else {
            log.info("Backend ASR skipped: capture too short (\(recording.durationSeconds, format: .fixed(precision: 3), privacy: .public)s) via \(self.providerName, privacy: .public)")
            return ""
        }
        guard recording.peakLevel >= Self.speechLevelThreshold else {
            log.info("Backend ASR skipped: no speech detected (peak \(recording.peakLevel, format: .fixed(precision: 3), privacy: .public)) via \(self.providerName, privacy: .public)")
            return ""
        }

        let text: String
        do {
            text = try await transcribeSegmented(recording.fileURL)
        } catch {
            log.error("Backend ASR transcription failed via \(self.providerName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        log.info("Backend ASR capture stopped; transcript length \(text.count, privacy: .public) via \(self.providerName, privacy: .public)")
        return text
    }

    /// Downconvert the recorded clip to 16 kHz / 16-bit / mono and split it into
    /// WAV segments small enough for the batch ASR size limit, then transcribe
    /// each and stitch the results. Sending the whole native-format clip in one
    /// request used to hard-fail past ~40 s ("录音太长", qwen3-asr-flash caps at
    /// 10 MB base64); downconvert + segment keeps the batch fallback unbounded.
    /// If decoding yields no samples we fall back to the original single-shot
    /// request rather than silently dropping audio.
    /// Post-upload ASR streaming is a provider-specific UX decision, not just a
    /// protocol capability. Qwen3-ASR-Flash streams tiny text deltas that make
    /// the capsule feel busy without improving the final insertion path, so the
    /// normal input-method route stays final-only. MiMo buffers and emits one
    /// cleaned transcript at done, so it keeps using its streaming API.
    nonisolated static func usesPostUploadStreamingPreview(forProvider provider: String) -> Bool {
        provider != "qwen-asr-flash"
    }

    private func transcribeSegmented(_ fileURL: URL) async throws -> String {
        let samples = try Self.decodeTo16kMonoInt16(fileURL)
        let segments = PCMWAVSegmenter.segmentedWAVs(
            samples: samples,
            maxSegmentBytes: PCMWAVSegmenter.defaultMaxSegmentBytes)
        guard !segments.isEmpty else {
            // Downconversion produced no samples (rare: a converter/read failure).
            // Only the raw clip is left — send it if it is already within the
            // request limit; never resurrect the oversized one-shot that produced
            // "录音太长". A clear decode error beats a misleading size error.
            let raw = try Data(contentsOf: fileURL)
            guard raw.count <= Self.maxRequestBytes else {
                throw CoachAPIError.message("音频解码失败,无法分段上传,请重试或缩短录音。")
            }
            return try await transcribeSegment(
                raw,
                mimeType: "audio/wav",
                stitchedPrefix: [])
        }
        var parts: [String] = []
        for (index, wav) in segments.enumerated() {
            log.info("Backend ASR segment \(index + 1, privacy: .public)/\(segments.count, privacy: .public) (\(wav.count, privacy: .public) bytes) via \(self.providerName, privacy: .public)")
            let text = try await transcribeSegment(
                wav,
                mimeType: "audio/wav",
                stitchedPrefix: parts)
            parts.append(text)
        }
        return TranscriptJoiner.join(parts)
    }

    private func transcribeSegment(
        _ audio: Data,
        mimeType: String,
        stitchedPrefix: [String]
    ) async throws -> String {
        if Self.usesPostUploadStreamingPreview(forProvider: providerName),
           let streamingClient = client as? any StreamingTranscriptionAPI {
            var segmentText = ""
            for try await event in streamingClient.streamTranscription(
                audio: audio,
                mimeType: mimeType,
                language: activeLocale.asrLanguageCode) {
                switch event {
                case .delta(let delta):
                    segmentText += delta
                    let stitched = TranscriptJoiner.join(stitchedPrefix + [segmentText])
                    partialContinuation?.yield(stitched)
                case .done:
                    let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        throw CoachAPIError.message("MiMo ASR 返回为空")
                    }
                    return trimmed
                case .failed(let message):
                    throw CoachAPIError.message(message)
                }
            }
            let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CoachAPIError.message("云端语音识别返回为空")
            }
            return trimmed
        }

        let result = try await client.transcribe(
            audio: audio,
            mimeType: mimeType,
            language: activeLocale.asrLanguageCode)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        partialContinuation?.yield(TranscriptJoiner.join(stitchedPrefix + [text]))
        return text
    }

    /// Read the whole recorded file and resample it to 16 kHz / 16-bit / mono PCM
    /// (mirrors the realtime sink's target format). Returns `[]` if the file has
    /// no frames or a converter can't be built, so the caller can fall back.
    nonisolated private static func decodeTo16kMonoInt16(_ url: URL) throws -> [Int16] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(PCMWAVSegmenter.sampleRate),
            channels: 1,
            interleaved: true),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw CoachAPIError.message("无法创建 16kHz mono PCM 转换器。")
        }
        let sourceFrames = AVAudioFrameCount(file.length)
        guard sourceFrames > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrames) else {
            return []
        }
        try file.read(into: inputBuffer)

        let ratio = Double(PCMWAVSegmenter.sampleRate) / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return []
        }

        let feed = SingleShotConverterFeed(inputBuffer)
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            feed.next(outStatus)
        }
        if let conversionError { throw conversionError }
        guard let channel = outputBuffer.int16ChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(outputBuffer.frameLength)))
    }

    public func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        profileStore.profile = profile
        log.info("Backend ASR capture profile set to \(profile.rawValue, privacy: .public) via \(self.providerName, privacy: .public)")
    }
}

extension CloudQwenSpeechCaptureService: SpeechCaptureProfileConfigurable {}

extension CloudQwenSpeechCaptureService: SpeechPartialTranscriptProviding {}

/// Feeds a single pre-read buffer to `AVAudioConverter` exactly once, then
/// reports end-of-stream. Wrapping the mutable `fed` flag and the non-Sendable
/// buffer in an `@unchecked Sendable` box keeps the converter's `@Sendable`
/// input block warning-free (the block is invoked synchronously within
/// `convert(to:error:withInputFrom:)`), matching this file's other wrappers.
private final class SingleShotConverterFeed: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var fed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if fed {
            outStatus.pointee = .endOfStream
            return nil
        }
        fed = true
        outStatus.pointee = .haveData
        return buffer
    }
}

private final class SpeechCaptureProfileStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SpeechCaptureProfile = .dictation

    var profile: SpeechCaptureProfile {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

private extension CaptureLocale {
    var asrLanguageCode: String {
        switch self {
        case .automatic: Locale.current.identifier.lowercased().hasPrefix("en") ? "en" : "zh"
        case .english: "en"
        case .chinese: "zh"
        case .mixed: "zh"
        }
    }
}

private final class CloudASRRecordingSession: @unchecked Sendable {
    let fileURL: URL
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let lock = NSLock()
    private let sampleRate: Double
    private var file: AVAudioFile?
    private var peak: Float = 0
    private var frameCount: Int = 0

    /// Highest input level (0...1) seen across the whole recording. Drives the silence gate.
    var peakLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// Total recorded length in seconds, from frames written. Drives the min-duration gate.
    var durationSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    init(
        fileURL: URL,
        format: AVAudioFormat,
        levelContinuation: AsyncStream<Float>.Continuation
    ) throws {
        self.fileURL = fileURL
        self.sampleRate = format.sampleRate
        self.levelContinuation = levelContinuation
        file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try file?.write(from: buffer)
        } catch {
            // The audio callback cannot throw. The user-facing failure will happen
            // when the backend receives an empty or invalid file.
        }

        frameCount += Int(buffer.frameLength)  // lock is already held for the whole method

        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(count)).squareRoot()
        let level = min(1, rms * 8)
        peak = max(peak, level)  // lock is already held for the whole method
        levelContinuation.yield(level)
    }

    func finish() {
        levelContinuation.finish()
        lock.lock()
        defer { lock.unlock() }
        file = nil
    }
}
