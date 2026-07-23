import AVFoundation
import Foundation
import ResponsayCore
import Speech

/// Minimal real-dictation loop for the onboarding sandbox step (issue 312):
/// hold → record → live partials into the 模拟编辑器 → release → final.
///
/// Deliberately independent of the production capture services: a sandbox
/// failure must never touch the real dictation path, and the production
/// `AppleSpeechCaptureService` doesn't expose a partial-transcript stream.
/// Same Apple recognizer, key-free, so the first-run experience needs zero
/// configuration. Speech-recognition authorization is requested explicitly
/// when the step appears (not on the first hotkey press later).
@MainActor
final class SandboxDictation {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// True once the OS speech-recognition permission is granted. Triggers the
    /// TCC dialog when undetermined; resolves without UI otherwise.
    static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start recording; `onPartial` fires on the main actor with the cumulative
    /// transcript as it grows. Throws when the recognizer/mic is unavailable —
    /// the caller falls back to the scripted simulation.
    func start(locale: String, onPartial: @escaping @MainActor (String) -> Void) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CoachAPIError.message("语音识别未授权")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable else {
            throw CoachAPIError.message("识别器不可用")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Idempotent: clear any lingering tap so a re-start can't hit AVAudioEngine's
        // one-tap-per-node assertion.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            request.append(buffer)
        }
        task = recognizer.recognitionTask(with: request) { @Sendable result, _ in
            guard let text = result?.bestTranscription.formattedString, !text.isEmpty else { return }
            Task { @MainActor in onPartial(text) }
        }
        engine.prepare()
        try engine.start()
    }

    /// Immediately tear down audio (tap + engine) — for view disappear / cancel, so the mic is
    /// released even when the user navigates away mid-recording without finalizing. Without this
    /// the engine keeps capturing and the macOS mic indicator stays on after leaving the step.
    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    /// Stop and give the recognizer a short grace window so the last partial
    /// (which the view keeps as the final text) can still land.
    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        try? await Task.sleep(nanoseconds: 350_000_000)
        task?.finish()
        request = nil
        task = nil
    }
}
