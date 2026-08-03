import Foundation
import Speech
import AVFoundation
import ResponsayCore
import OSLog
import os

/// Apple on-device speech capture (`SFSpeechRecognizer`). The first capture service moved
/// into the shared `ResponsaySpeech` package (issue 354 tracer): pure Swift + Apple
/// frameworks, so it compiles for both macOS and iOS. The only macOS-specific touch is the
/// preferred-mic device selection, guarded by `#if os(macOS)`.
@MainActor
public final class AppleSpeechCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "speech")
    #if os(macOS)
    // 蓝牙麦克风修复: AVCaptureSession binds a specific device up front (like getUserMedia), so the
    // BT default can't poison the input format. iOS keeps AVAudioEngine (no device override there).
    private var recorder: AVCaptureAudioRecorder?
    #else
    private let engine = AVAudioEngine()
    #endif
    private var recognizer: SFSpeechRecognizer?
    private var session: RecognitionSession?
    private var task: SFSpeechRecognitionTask?
    private var captureProfile: SpeechCaptureProfile = .dictation

    /// Live RMS level (0...1) during recording, for the waveform. Rebuilt each `start()`.
    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    private var levelContinuation: AsyncStream<Float>.Continuation?

    public init() {}

    public func start(locale: CaptureLocale) throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            throw CoachAPIError.message("语音识别未授权。请到 系统设置 › 隐私与安全性 › 语音识别 开启。")
        case .notDetermined:
            // TCC invokes this completion on a background queue. It MUST be @Sendable
            // so it does not inherit this @MainActor context — otherwise the runtime
            // main-actor isolation check crashes when it runs off the main thread.
            SFSpeechRecognizer.requestAuthorization { @Sendable _ in }
            throw CoachAPIError.message("正在请求语音识别授权,授权后请再按一次。")
        case .authorized: break
        @unknown default: break
        }
        let recognizerLocale = locale == .automatic ? Locale.current : Locale(identifier: locale.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: recognizerLocale),
              recognizer.isAvailable else {
            throw CoachAPIError.message("Speech recognizer unavailable for \(locale.rawValue).")
        }
        self.recognizer = recognizer

        let session = RecognitionSession()
        session.request.shouldReportPartialResults = true
        // Don't force on-device: assets download lazily and would yield empty
        // transcripts on first use (review #2). Let the system pick (server when needed).
        session.request.requiresOnDeviceRecognition = false
        self.session = session

        // Rebuild the level stream for this recording. `AsyncStream.Continuation` is
        // Sendable, so the @Sendable tap can yield to it without touching the main actor.
        let (levelStream, levelCont) = AsyncStream.makeStream(of: Float.self)
        levels = levelStream
        levelContinuation = levelCont

        // The audio source + recognition handler run off the main actor. Both are @Sendable
        // (so they run nonisolated) and touch only Sendable values (`session`, `levelCont`).
        task = recognizer.recognitionTask(with: session.request) { @Sendable result, _ in
            if let result { session.update(result.bestTranscription.formattedString) }
        }
        #if os(macOS)
        let recorder = AVCaptureAudioRecorder()
        self.recorder = recorder
        try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID) { @Sendable buffer in
            session.append(buffer) { level in levelCont.yield(level) }
        }
        #else
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Idempotent: clear any tap a not-yet-finished async stop() left behind, so a rapid
        // re-start can't hit AVAudioEngine's one-tap-per-node assertion and wedge the recorder.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            session.append(buffer) { level in levelCont.yield(level) }
        }
        engine.prepare()
        try engine.start()
        #endif
        log.info("Speech capture started for \(locale.rawValue, privacy: .public)")
    }

    public func stop() async throws -> String {
        #if os(macOS)
        recorder?.stop()
        recorder = nil
        #else
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #endif
        levelContinuation?.finish()
        levelContinuation = nil
        session?.request.endAudio()
        // 给识别器一点时间产出最终结果
        try? await Task.sleep(nanoseconds: 350_000_000)
        task?.finish()
        let text = session?.transcript ?? ""
        session = nil
        task = nil
        log.info("Speech capture stopped; transcript length \(text.count, privacy: .public)")
        return text
    }

    public func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfile = profile
        log.info("Apple speech capture profile set to \(profile.rawValue, privacy: .public)")
    }
}

extension AppleSpeechCaptureService: SpeechCaptureProfileConfigurable {}

/// Thread-safe holder for the live recognition request + latest transcript.
///
/// `@unchecked Sendable` on purpose: the off-main speech callbacks (audio tap,
/// recognition handler) need to touch this without main-actor isolation.
/// `SFSpeechAudioBufferRecognitionRequest.append` is safe from the audio thread,
/// and the transcript is guarded by a lock — so sharing across threads is safe.
private final class RecognitionSession: @unchecked Sendable {
    let request = SFSpeechAudioBufferRecognitionRequest()
    private let transcriptLock = OSAllocatedUnfairLock(initialState: "")

    func append(_ buffer: AVAudioPCMBuffer, level: @Sendable (Float) -> Void) {
        request.append(buffer)
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(count)).squareRoot()
        level(min(1, rms * 8))  // empirically amplified into 0...1
    }
    func update(_ text: String) { transcriptLock.withLock { $0 = text } }
    var transcript: String { transcriptLock.withLock { $0 } }
}
