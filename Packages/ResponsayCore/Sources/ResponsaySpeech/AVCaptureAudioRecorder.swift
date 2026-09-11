#if os(macOS)
import AVFoundation
import CoreMedia
import OSLog
import ResponsayCore

/// Microphone seam shared by the production recorder and deterministic local capture adapters.
public protocol SpeechAudioRecording: AnyObject {
    func start(
        preferredUID: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) throws
    func stop() throws
}

/// Microphone recorder built on `AVCaptureSession` (macOS).
///
/// Unlike `AVAudioEngine.inputNode` — which realizes at the *system default* device and keeps
/// that device's format even after you switch `kAudioOutputUnitProperty_CurrentDevice` — an
/// `AVCaptureSession` is bound to a specific `AVCaptureDevice` chosen up front, exactly like the
/// web `getUserMedia({audio:{deviceId}})` path. So a Bluetooth headset being the system default
/// (HFP, 16 kHz) can't poison the input format or kill capture of the built-in mic (the bug where
/// the tap received zero buffers).
///
/// `AVCaptureAudioDataOutput.audioSettings` is asked for 16 kHz mono Float32, so the delivered
/// `AVAudioPCMBuffer`s are already in the pipeline's target format — no resampling here. Each
/// capture service keeps its own consumer (`append`) and level metering unchanged; only the audio
/// *source* changes from the engine tap to this recorder's `onBuffer` callback (fired on a private
/// serial queue, like the old tap).
public final class AVCaptureAudioRecorder: NSObject, @unchecked Sendable, SpeechAudioRecording {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "avcapture-audio")
    private var session = AVCaptureSession()
    private var output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.semanticcraft.responsay.avcapture-audio")
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var generation = UUID()
    private var terminalFailure: String?
    private var observers: [NSObjectProtocol] = []
    private var onFailure: (@Sendable (String) -> Void)?

    /// The format the recorder delivers: 16 kHz mono Float32 — what every downstream consumer
    /// (file writer / accumulator / SFSpeech request) expects.
    public static let deliveredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let makeSession: @Sendable () -> AVCaptureSession
    private let configure: @Sendable (AVCaptureSession, AVCaptureAudioDataOutput, String) throws -> AnyObject

    public override init() {
        makeSession = { AVCaptureSession() }
        configure = Self.configureSession
        super.init()
    }

    /// Tests replace only session startup/configuration; notification and queue handling stay real.
    init(makeSession: @escaping @Sendable () -> AVCaptureSession,
         configure: @escaping @Sendable (AVCaptureSession, AVCaptureAudioDataOutput, String) throws -> AnyObject) {
        self.makeSession = makeSession
        self.configure = configure
        super.init()
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Start capturing from `preferredUID` (an `AVCaptureDevice.uniqueID`), or the default audio
    /// input when empty / not found. `onBuffer` is invoked on a private serial queue.
    public func start(
        preferredUID: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) throws {
        try queue.sync {
            stopOnQueue()
            terminalFailure = nil
            generation = UUID()
            // A fresh session and output give delayed notifications/buffers a stable identity.
            session = makeSession()
            output = AVCaptureAudioDataOutput()
            let device: AnyObject
            do { device = try configure(session, output, preferredUID) }
            catch { stopOnQueue(); throw error }
            output.setSampleBufferDelegate(self, queue: queue)
            self.onBuffer = onBuffer
            self.onFailure = onFailure
            let current = session
            for name in [AVCaptureSession.runtimeErrorNotification,
                         AVCaptureSession.didStopRunningNotification,
                         AVCaptureSession.wasInterruptedNotification] {
                observe(name, object: current, generation: generation)
            }
            observe(AVCaptureDevice.wasDisconnectedNotification, object: device, generation: generation)
            session.startRunning()
            guard session.isRunning else {
                stopOnQueue()
                throw CoachAPIError.message("麦克风未能开始录音，请检查输入设备后重试。")
            }
        }
    }

    private static func configureSession(
        _ session: AVCaptureSession, _ output: AVCaptureAudioDataOutput, _ preferredUID: String
    ) throws -> AnyObject {
        guard let device = Self.device(preferredUID: preferredUID) else {
            throw CoachAPIError.message("找不到可用的麦克风设备。请到系统设置检查输入。")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CoachAPIError.message("无法配置所选麦克风。")
        }
        session.addInput(input)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        session.addOutput(output)
        return device
    }

    private func observe(_ name: Notification.Name, object: AnyObject, generation: UUID) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name, object: object, queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == generation, let failure = self.onFailure else { return }
                let message = "麦克风连接已中断或录音失败，请检查输入设备后重新录音。"
                self.terminalFailure = message
                self.stopOnQueue()
                failure(message)
            }
        })
    }

    public func stop() throws {
        try queue.sync {
            stopOnQueue()
            if let terminalFailure { throw CoachAPIError.message(terminalFailure) }
        }
    }

    private func stopOnQueue() {
        onBuffer = nil
        onFailure = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    private static func device(preferredUID: String) -> AVCaptureDevice? {
        let all = AVCaptureDevice.devices(for: .audio)
        let resolved: AVCaptureDevice? =
            if !preferredUID.isEmpty, let match = all.first(where: { $0.uniqueID == preferredUID }) {
                match
            } else {
                AVCaptureDevice.default(for: .audio)
            }
        guard let resolved else { return nil }
        // A Bluetooth headset mic drags the headset into the HFP call profile (music squashed
        // while recording, volume burst when it flips back to A2DP on stop) — capture from the
        // built-in mic instead so the headset stays on A2DP. See AudioInputDeviceSelector.
        if let fallbackUID = AudioInputDeviceSelector.builtInFallbackUID(insteadOf: resolved.uniqueID),
           let builtIn = all.first(where: { $0.uniqueID == fallbackUID }) {
            return builtIn
        }
        return resolved
    }
}

extension AVCaptureAudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === self.output, let onBuffer, let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer(buffer)
    }

    /// Copy a delivered `CMSampleBuffer` (already 16 kHz mono Float32 via `audioSettings`) into an
    /// `AVAudioPCMBuffer` the existing consumers accept. nil on a malformed/empty buffer.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        var asbd = asbdPointer.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
#endif
