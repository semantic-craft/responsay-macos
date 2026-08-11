#if os(macOS)
import AVFoundation
import CoreMedia
import OSLog
import ResponsayCore

/// Microphone seam shared by the production recorder and deterministic local capture adapters.
public protocol SpeechAudioRecording: AnyObject {
    func start(
        preferredUID: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws
    func stop()
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
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.semanticcraft.responsay.avcapture-audio")
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// The format the recorder delivers: 16 kHz mono Float32 — what every downstream consumer
    /// (file writer / accumulator / SFSpeech request) expects.
    public static let deliveredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    public override init() { super.init() }

    /// Start capturing from `preferredUID` (an `AVCaptureDevice.uniqueID`), or the default audio
    /// input when empty / not found. `onBuffer` is invoked on a private serial queue.
    public func start(
        preferredUID: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        guard let device = Self.device(preferredUID: preferredUID) else {
            throw CoachAPIError.message("找不到可用的麦克风设备。请到 系统设置 › 声音 › 输入 检查。")
        }
        self.onBuffer = onBuffer
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }   // idempotent on a reused recorder
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw CoachAPIError.message("无法使用所选麦克风：\(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CoachAPIError.message("无法使用所选麦克风「\(device.localizedName)」。")
        }
        session.addInput(input)
        if !session.outputs.contains(output) {
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw CoachAPIError.message("无法配置音频采集输出。")
            }
            session.addOutput(output)
        }
        session.commitConfiguration()
        session.startRunning()
        log.info("AVCapture recording started: \(device.localizedName, privacy: .public)")
    }

    public func stop() {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.commitConfiguration()
        onBuffer = nil
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
        guard let onBuffer, let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
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
