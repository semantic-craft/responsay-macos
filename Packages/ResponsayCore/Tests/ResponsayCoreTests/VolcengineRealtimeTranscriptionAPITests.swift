import Foundation
import Testing
@testable import ResponsayCore

/// The capture layer hands `transcribe(audio:)` a 16 kHz/mono/16-bit PCM **WAV**;
/// the Volcengine stream wants raw PCM frames (format pcm/codec raw). This pins the
/// header-strip + chunking that bridges the two. The live socket drive is the HITL
/// boundary (mic + network) and isn't unit-tested.
@Suite("VolcengineRealtimeTranscriptionAPI")
struct VolcengineRealtimeTranscriptionAPITests {

    @Test func pcmFramesStripsWavHeaderAndChunks() {
        let pcm = Data((0..<10).map { UInt8($0) })   // 10 bytes of "PCM"
        let wav = Self.makeWAV(pcm: pcm)
        let frames = VolcengineRealtimeTranscriptionAPI.pcmFrames(fromWAV: wav, frameBytes: 4)

        #expect(frames.allSatisfy { $0.count <= 4 })
        #expect(frames.reduce(Data(), +) == pcm)   // reassemble → exactly the PCM, no header
    }

    @Test func pcmFramesFallsBackWhenNoDataChunk() {
        let raw = Data((0..<7).map { UInt8($0) })    // not a WAV — no "data" tag
        let frames = VolcengineRealtimeTranscriptionAPI.pcmFrames(fromWAV: raw, frameBytes: 3)
        #expect(frames.reduce(Data(), +) == raw)
        #expect(frames.count == 3)                   // 3+3+1
    }

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
            try await api.transcribe(audio: Data(), mimeType: "audio/wav", language: "zh")
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

    // Minimal canonical 44-byte PCM WAV header + samples.
    private static func makeWAV(pcm: Data) -> Data {
        var d = Data()
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count)); d.append(pcm)
        return d
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
