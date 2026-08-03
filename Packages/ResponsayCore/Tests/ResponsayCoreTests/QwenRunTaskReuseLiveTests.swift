import Foundation
import Testing
@testable import ResponsayCore

/// Opt-in public-network measurement for #52. The same synthetic/non-sensitive 16 kHz mono
/// Int16 PCM fixture is sent twice through one session. Only run-task -> task-started timings are
/// printed; the key, fixture path, and recognition result never leave process memory.
/// Run with `RESPONSAY_QWEN_ASR_LIVE=1`, `DASHSCOPE_API_KEY`, and `QWEN_ASR_PCM_PATH` set.
@Suite(
    "Qwen run-task connection reuse live measurement",
    .enabled(if: ProcessInfo.processInfo.environment["RESPONSAY_QWEN_ASR_LIVE"] == "1")
)
struct QwenRunTaskReuseLiveTests {
    @Test("compare fresh and reused run-task startup latency")
    func compareStartupLatency() async throws {
        let environment = ProcessInfo.processInfo.environment
        let apiKey = try #require(environment["DASHSCOPE_API_KEY"],
                                  "DASHSCOPE_API_KEY is required for this opt-in test.")
        let pcmPath = try #require(environment["QWEN_ASR_PCM_PATH"],
                                  "QWEN_ASR_PCM_PATH is required for this opt-in test.")
        let pcm = try Data(contentsOf: URL(fileURLWithPath: pcmPath))
        #expect(!pcm.isEmpty)

        let session = QwenRunTaskSession()
        let recorder = StartMetricRecorder()
        let config = QwenRunTaskCaptureConfig(
            endpoint: .init(region: .china),
            apiKey: apiKey,
            captureLocale: .mixed,
            heartbeat: true,
            multiThresholdModeEnabled: true)

        do {
            for _ in 0..<2 {
                let audio = QwenReplayableAudioBuffer()
                let feeder = Task {
                    let frameSize = 3_200 // 100 ms at 16 kHz mono Int16.
                    for start in stride(from: 0, to: pcm.count, by: frameSize) {
                        let end = min(start + frameSize, pcm.count)
                        audio.append(pcm.subdata(in: start ..< end))
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    audio.finish()
                }
                do {
                    _ = try await session.transcribe(
                        config: config,
                        audio: audio,
                        onTaskStarted: { await recorder.append($0) })
                    try await feeder.value
                } catch {
                    feeder.cancel()
                    audio.finish()
                    throw error
                }
            }
        } catch {
            await session.shutdown()
            throw error
        }
        await session.shutdown()

        let values = await recorder.values
        #expect(values.count == 2)
        guard values.count == 2 else { return }
        #expect(!values[0].reusedConnection)
        #expect(values[1].reusedConnection)

        let freshMs = Double(values[0].runTaskToStartedNanos) / 1_000_000
        let reusedMs = Double(values[1].runTaskToStartedNanos) / 1_000_000
        let savedMs = freshMs - reusedMs
        print(String(format:
            "QWEN_REUSE_LATENCY fresh_ms=%.1f reused_ms=%.1f saved_ms=%.1f reduced=%@",
            freshMs, reusedMs, savedMs, reusedMs < freshMs ? "true" : "false"))
    }
}

private actor StartMetricRecorder {
    private(set) var values: [QwenRunTaskStartMetric] = []

    func append(_ metric: QwenRunTaskStartMetric) {
        values.append(metric)
    }
}
