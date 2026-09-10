import Foundation
import Testing
@testable import ResponsayCore

@Suite("VolcengineRealtimeTranscriptionAPI")
struct VolcengineRealtimeTranscriptionAPITests {

    @Test func deferredHotwordsReachTheFullClientRequestPayload() async throws {
        let api = VolcengineRealtimeTranscriptionAPI(
            endpoint: VolcengineRealtimeEndpoint(apiKey: "test"),
            config: VolcengineRealtimeConfig(hotwords: ["stale"]),
            hotwordsProvider: { ["Current Screen", "Westlaw"] })

        let config = await api.resolvedRequestConfig()
        let frame = VolcengineRealtimeProtocol.fullClientRequest(config: config)
        let json = try #require(
            try JSONSerialization.jsonObject(
                with: Gzip.decompress(Data(frame.suffix(from: 8)))) as? [String: Any])
        let request = try #require(json["request"] as? [String: Any])
        let corpus = try #require(request["corpus"] as? [String: Any])
        let context = try #require(corpus["context"] as? String)
        let contextJSON = try #require(
            try JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any])
        let hotwords = try #require(contextJSON["hotwords"] as? [[String: Any]])

        #expect(hotwords.compactMap { $0["word"] as? String } == ["Current Screen", "Westlaw"])
    }

    @Test func cancellationDuringDeferredConfigNeverStartsTheSocket() async {
        let provider = SuspendedVolcHotwordsProvider()
        let socketWasCreated = LockedBoolean()
        let api = VolcengineRealtimeTranscriptionAPI(
            endpoint: VolcengineRealtimeEndpoint(apiKey: "test"),
            hotwordsProvider: { await provider.value() },
            webSocketTaskProvider: { _ in
                socketWasCreated.setTrue()
                fatalError("cancelled configuration must not create a WebSocket")
            })
        let transcription = Task {
            try await api.transcribe(audio: AsyncStream { $0.finish() })
        }
        await provider.waitUntilStarted()

        transcription.cancel()
        await provider.resume(returning: [])

        do {
            _ = try await transcription.value
            Issue.record("cancelled transcription unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancellation is observed before any external transport is created.
        } catch {
            Issue.record("unexpected cancellation error: \(error)")
        }
        #expect(!socketWasCreated.value)
    }

}

private actor SuspendedVolcHotwordsProvider {
    private var continuation: CheckedContinuation<[String], Never>?

    func value() async -> [String] {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    func resume(returning value: [String]) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool { lock.withLock { storage } }
    func setTrue() { lock.withLock { storage = true } }
}
