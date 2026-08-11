import AVFoundation
import Foundation
import OSLog
import ResponsayCore
import ResponsaySpeech
import os

/// In-process offline speech capture for any sherpa-onnx whole-utterance model
/// (SenseVoice, Qwen3-ASR, …). Records from the mic, resamples to 16 kHz mono,
/// and on `stop()` runs the recognizer locally — no Node backend, no network.
@MainActor
final class OfflineSherpaCaptureService: SpeechCaptureService, LocalEngineResidencyControllable {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "offline-sherpa-capture")
    // 蓝牙麦克风修复: capture via AVCaptureSession (binds a specific device up front, like
    // getUserMedia) instead of AVAudioEngine — whose inputNode keeps the BT default's stale
    // 16 kHz format and then delivers zero buffers when the built-in mic is selected.
    private var recorder: AVCaptureAudioRecorder?
    private let spec: LocalModelSpec
    private let isModelInstalled: @Sendable () -> Bool
    private let makeRecognizer: @Sendable () throws -> any OfflineSherpaRecognizer
    private var accumulator: PCMAccumulator?
    private var captureProfile: SpeechCaptureProfile = .dictation
    /// Loaded lazily on first `start()`, cached across recordings, released per
    /// the `localEngineTTL` keep-loaded policy after each utterance.
    private var recognizer: (any OfflineSherpaRecognizer)?
    private var releaseTask: Task<Void, Never>?
    /// True between `start()` and the end of `stop()` — guards manual unload.
    private(set) var isCapturing = false

    private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    private var levelContinuation: AsyncStream<Float>.Continuation?

    init(
        spec: LocalModelSpec,
        isModelInstalled: (@Sendable () -> Bool)? = nil,
        makeRecognizer: @escaping @Sendable () throws -> any OfflineSherpaRecognizer
    ) {
        self.spec = spec
        self.isModelInstalled = isModelInstalled ?? { spec.isInstalled }
        self.makeRecognizer = makeRecognizer
        LocalEngineResidency.shared.register(self, id: spec.id)
    }

    func start(locale: CaptureLocale) throws {
        guard isModelInstalled() else {
            throw CoachAPIError.message(
                "\(spec.displayName) 模型未安装。请到 设置 › 本地模型 下载后再使用。")
        }
        releaseTask?.cancel()
        releaseTask = nil
        if recognizer == nil { setRecognizer(try makeRecognizer()) }

        let (levelStream, levelCont) = AsyncStream.makeStream(of: Float.self)
        levels = levelStream
        levelContinuation = levelCont

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        else { throw CoachAPIError.message("无法创建 16kHz 音频格式。") }
        // The recorder already delivers 16 kHz mono Float, so the accumulator's converter is identity.
        let acc = try PCMAccumulator(
            inputFormat: AVCaptureAudioRecorder.deliveredFormat, targetFormat: targetFormat)
        accumulator = acc

        let recorder = AVCaptureAudioRecorder()
        self.recorder = recorder
        try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID) { @Sendable buffer in
            acc.append(buffer) { level in levelCont.yield(level) }
        }
        isCapturing = true
        log.info("offline capture started: \(self.spec.id, privacy: .public)")
    }

    func stop() async throws -> String {
        defer { isCapturing = false }
        recorder?.stop()
        recorder = nil
        levelContinuation?.finish()
        levelContinuation = nil

        guard let accumulator, let recognizer else { return "" }
        self.accumulator = nil
        let samples = accumulator.drain()
        guard !samples.isEmpty else { return "" }

        let text = try await Task.detached(priority: .userInitiated) {
            try recognizer.transcribeText(samples, sampleRate: 16_000)
        }.value
        log.info("offline transcript length \(text.count, privacy: .public)")
        scheduleRelease()
        return text
    }

    func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfile = profile
    }

    /// Release the cached recognizer per the `localEngineTTL` keep-loaded policy.
    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = nil
        guard let idle = EngineKeepAlive(raw: keepLoadedRaw).idleNanoseconds else { return }   // keepForever
        if idle == 0 { setRecognizer(nil); return }
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: idle)
            guard !Task.isCancelled else { return }
            self?.setRecognizer(nil)
        }
    }

    /// Set/clear the cached recognizer and mirror residency to the shared record.
    private func setRecognizer(_ value: (any OfflineSherpaRecognizer)?) {
        recognizer = value
        LocalEngineResidency.shared.setResident(spec.id, value != nil)
    }

    private var keepLoadedRaw: String {
        UserDefaults.standard.string(forKey: "localEngineTTL") ?? "5"
    }

    // MARK: - LocalEngineResidencyControllable (manual load/unload from Settings)

    /// "Load now" — preload the recognizer. A manual preload re-arms the keep-alive
    /// only for timed policies; under 即时释放 (0) it stays resident until the next
    /// capture or a manual unload, so the click isn't undone immediately.
    func preloadEngine() throws {
        guard isModelInstalled() else {
            throw CoachAPIError.message(
                "\(spec.displayName) 模型未安装。请到 设置 › 本地模型 下载后再使用。")
        }
        releaseTask?.cancel()
        releaseTask = nil
        if recognizer == nil { setRecognizer(try makeRecognizer()) }
        if case .minutes = EngineKeepAlive(raw: keepLoadedRaw) { scheduleRelease() }
    }

    /// openless-style background prewarm (`spawn_blocking` + resident cache): build the
    /// recognizer off the main thread when this engine is selected, so selecting it never
    /// freezes the UI and the first hotkey finds it resident (LATENCY-MODELLOAD-001).
    /// Best-effort — a failure just leaves the lazy load to the first `start()`. No-op if
    /// already loaded, capturing, or the model isn't installed.
    func preloadEngineInBackground() {
        guard isModelInstalled(), recognizer == nil, !isCapturing else { return }
        let make = makeRecognizer
        let id = spec.id
        Task.detached(priority: .utility) {
            guard let built = try? make() else {
                Logger(subsystem: AppBrand.loggerSubsystem, category: "offline-sherpa-capture")
                    .info("background preload failed for \(id, privacy: .public)")
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.recognizer == nil, !self.isCapturing else { return }
                self.setRecognizer(built)
                if case .minutes = EngineKeepAlive(raw: self.keepLoadedRaw) { self.scheduleRelease() }
            }
        }
    }

    /// "Unload now" — free the recognizer immediately; ignored mid-capture.
    func unloadEngine() {
        guard !isCapturing else { return }
        releaseTask?.cancel()
        releaseTask = nil
        setRecognizer(nil)
    }
}

extension OfflineSherpaCaptureService: SpeechCaptureProfileConfigurable {}

/// Resamples incoming mic buffers to 16 kHz mono Float and accumulates them.
/// `@unchecked Sendable`: the audio tap calls `append` serially on the I/O
/// thread; the converter is used only there, and the sample buffer is locked.
private final class PCMAccumulator: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let inputSampleRate: Double
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())

    init(inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CoachAPIError.message("无法创建音频重采样器。")
        }
        self.converter = converter
        self.targetFormat = targetFormat
        self.inputSampleRate = inputFormat.sampleRate
    }

    func append(_ buffer: AVAudioPCMBuffer, level: @Sendable (Float) -> Void) {
        let ratio = targetFormat.sampleRate / inputSampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return }

        var fed = false
        var convError: NSError?
        converter.convert(to: out, error: &convError) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard convError == nil, out.frameLength > 0, let channel = out.floatChannelData else {
            return
        }
        let count = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: count))
        samples.withLock { $0.append(contentsOf: chunk) }

        var sumOfSquares: Float = 0
        for value in chunk { sumOfSquares += value * value }
        level(min(1, (sumOfSquares / Float(count)).squareRoot() * 8))
    }

    func drain() -> [Float] {
        samples.withLock { current in
            let copy = current
            current.removeAll(keepingCapacity: false)
            return copy
        }
    }
}
