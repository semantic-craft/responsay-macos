#if os(macOS)
import AVFoundation
import Foundation
import ResponsayCore

/// Streams microphone PCM while recording; exposes only the whole-utterance final.
@MainActor
public final class VolcengineStreamingCaptureService: SpeechCaptureService {
    public typealias Transcribe = @Sendable (AsyncStream<Data>) async throws -> String
    private let transcriber: () throws -> Transcribe
    private let audioRecorder: () -> any SpeechAudioRecording
    private let requireMicPermission: () throws -> Void
    private var recorder: (any SpeechAudioRecording)?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var transcriptionTask: Task<String, Error>?
    public private(set) var levels: AsyncStream<Float> = AsyncStream { $0.finish() }
    public var captureCapability: SpeechCaptureCapability {
        .init(partialStyle: .none, needsEchoFilter: true)
    }

    public init(
        transcriber: @escaping () throws -> Transcribe,
        audioRecorder: @escaping () -> any SpeechAudioRecording = { AVCaptureAudioRecorder() },
        requireMicPermission: @escaping () throws -> Void
    ) {
        self.transcriber = transcriber
        self.audioRecorder = audioRecorder
        self.requireMicPermission = requireMicPermission
    }

    private let failureState = SpeechCaptureFailureState()
    public var captureFailures: AsyncStream<String> { failureState.stream }

    public func start(locale: CaptureLocale) throws {
        guard transcriptionTask == nil else { throw CoachAPIError.message("已有语音采集正在进行。") }
        let generation = failureState.begin()
        try requireMicPermission()
        let transcribe = try transcriber()
        let (audio, audioCont) = AsyncStream.makeStream(of: Data.self)
        let (levels, levelCont) = AsyncStream.makeStream(of: Float.self)
        self.levels = levels
        audioContinuation = audioCont
        levelContinuation = levelCont
        let task = Task.detached {
            defer { audioCont.finish() }
            return try await transcribe(audio)
        }
        transcriptionTask = task
        if let task = transcriptionTask {
            Task { [weak self] in
                _ = await task.result
                guard let self else { return }
                self.failureState.fail("语音识别连接已结束，请重新录音。", generation: generation) {
                    self.captureFailed()
                }
            }
        }

        let recorder = audioRecorder()
        self.recorder = recorder
        do {
            try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID, onBuffer: { buffer in
                guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }
                let floats = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
                let power = floats.reduce(Float(0)) { $0 + $1 * $1 } / Float(floats.count)
                levelCont.yield(min(1, power.squareRoot() * 8))
                audioCont.yield(QwenRealtimePCM.int16LE(from: floats))
            }, onFailure: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.failureState.fail(message, generation: generation) { self.captureFailed() }
                }
            })
        } catch {
            try? recorder.stop()
            audioCont.finish()
            levelCont.finish()
            task.cancel()
            cleanup()
            throw error
        }
    }

    #if os(macOS)
    public func cancel() async {
        try? failureState.end()
        captureFailed()
    }

    private func captureFailed() {
        try? recorder?.stop()
        levelContinuation?.finish()
        transcriptionTask?.cancel()
        audioContinuation?.finish()
        cleanup()
    }
    #endif

    public func stop() async throws -> String {
        do { try recorder?.stop() } catch {
            await cancel()
            throw error
        }
        recorder = nil
        try failureState.end()
        levelContinuation?.finish()
        audioContinuation?.finish()
        guard let task = transcriptionTask else { return "" }
        defer { cleanup() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await task.value }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    task.cancel()
                    throw CoachAPIError.message("等待豆包语音识别最终结果超时。")
                }
                defer { group.cancelAll() }
                return try await group.next() ?? ""
            }
        } onCancel: { task.cancel() }
    }

    private func cleanup() {
        recorder = nil
        audioContinuation = nil
        levelContinuation = nil
        transcriptionTask = nil
    }
}
#endif
