import Foundation
import XCTest
@testable import ResponsayCore
@testable import ResponsayMac

/// Opt-in real-service acceptance for the Qwen streaming ASR path shipped by the app.
///
/// The test consumes a caller-supplied 16 kHz mono Int16 PCM fixture and the existing ASR
/// Keychain credential. Normal local and CI runs skip it, and neither the key nor transcript is
/// logged. It intentionally exercises the first-batch official capabilities in two bounded tasks:
/// an unassisted baseline, followed by the exact same audio after a real `matis` → `Metis` edit
/// has passed through the explicit-correction learner. The enhanced request covers
/// instant vocabulary, mixed-language hints, context, heartbeat, multi-threshold segmentation,
/// and an in-task context refresh.
@MainActor
final class QwenRunTaskASRLiveTests: XCTestCase {
    func testEnhancedStreamingRecognitionAgainstConfiguredAccount() async throws {
        let environment = ProcessInfo.processInfo.environment
        let liveDefaultsName = "com.semanticcraft.responsay.qwen-asr-live-test"
        let liveDefaults = try XCTUnwrap(UserDefaults(suiteName: liveDefaultsName))
        guard environment["RESPONSAY_QWEN_ASR_LIVE"] == "1" || liveDefaults.bool(forKey: "enabled") else {
            throw XCTSkip("Set RESPONSAY_QWEN_ASR_LIVE=1 to run Qwen ASR live acceptance.")
        }
        defer { liveDefaults.removePersistentDomain(forName: liveDefaultsName) }
        let pcmPath = try XCTUnwrap(
            environment["QWEN_ASR_PCM_PATH"] ?? liveDefaults.string(forKey: "pcmPath"))
        let pcm = try Data(contentsOf: URL(fileURLWithPath: pcmPath))
        XCTAssertFalse(pcm.isEmpty)

        let apiKey = try XCTUnwrap(BYOKKeychain.read("byok.qwen-asr-flash"))
        let baseline = try await transcribe(pcm, apiKey: apiKey)

        var learnedProposal: HotwordCandidateProposal?
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { false },
            isExplicitCorrectionLearningEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .confirmEveryTime },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in learnedProposal = proposal; return true },
            record: { _, _ in true })
        let learning = processor.processExplicitCorrectionSynchronously(HotwordCorrectionContext(
            insertedText: "The project codename is matis.",
            userFinalText: "The project codename is Metis.",
            appName: nil,
            windowTitle: nil))
        let proposal = try XCTUnwrap(learnedProposal)
        let source = try XCTUnwrap(proposal.sourceTerm)
        XCTAssertEqual(learning.addedTerms, ["Metis"])

        var contextBuffer = RecentASRContextBuffer()
        contextBuffer.record("The project codename is matis.", scope: "live-test")
        let enhancedContext = contextBuffer.context(
            for: "live-test", learnedAliases: [source: proposal.term])
        XCTAssertEqual(enhancedContext, ["The project codename is Metis."])

        let enhanced = try await transcribe(
            pcm,
            apiKey: apiKey,
            hotwords: learning.addedTerms + ["Responsay"],
            context: enhancedContext)
        XCTAssertFalse(baseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(
            baseline.localizedCaseInsensitiveContains("Metis"),
            "The live fixture is not discriminating because the unassisted baseline already contains Metis.")
        XCTAssertTrue(
            enhanced.localizedCaseInsensitiveContains("Metis"),
            "Enhanced decoding did not preserve the learned canonical hotword.")
    }

    private func transcribe(
        _ pcm: Data,
        apiKey: String,
        hotwords: [String] = [],
        context: [String] = []
    ) async throws -> String {
        let endpoint = QwenRunTaskEndpoint(region: .china)
        var request = URLRequest(url: endpoint.url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let client = QwenRunTaskASRClient(transport: socket)
        let receiver = Task<String, Error> {
            while true {
                let event = try await client.receive()
                guard let update = await client.handleEvent(event) else { continue }
                switch update {
                case .partial:
                    continue
                case let .final(text):
                    return text
                case let .failed(message):
                    throw LiveAcceptanceError.server(message ?? "unknown server failure")
                }
            }
        }

        try await client.sendRunTask(
            model: QwenRunTaskEndpoint.defaultModel,
            hotwords: hotwords,
            languageHints: ["zh", "en"],
            context: context,
            heartbeat: true,
            semanticPunctuationEnabled: false,
            multiThresholdModeEnabled: true)
        guard await client.awaitStarted() else {
            receiver.cancel()
            throw LiveAcceptanceError.taskDidNotStart
        }
        try await client.sendContinueTask(context: context)

        // 100 ms of 16 kHz mono Int16 audio per frame, paced in real time.
        let frameSize = 3_200
        for start in stride(from: 0, to: pcm.count, by: frameSize) {
            let end = min(start + frameSize, pcm.count)
            try await client.sendAudio(pcm.subdata(in: start ..< end))
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await client.finish()

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await receiver.value }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw LiveAcceptanceError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }

    private enum LiveAcceptanceError: Error {
        case server(String)
        case taskDidNotStart
        case timeout
    }
}
