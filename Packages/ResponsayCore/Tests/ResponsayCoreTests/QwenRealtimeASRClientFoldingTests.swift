import Foundation
import Testing
@testable import ResponsayCore

/// qwen3-asr-flash-realtime folds into the same Plan-B `TranscriptUpdate` contract as
/// the 火山 client: live `text+stash` → `.partial(preview:)` (capsule only), and the
/// `completed` transcript → `.final(transcript:)` (source of truth for skills + insertion).
/// Same shape both engines → the capture layer treats them identically.
@Suite("QwenRealtimeASRClient folding")
struct QwenRealtimeASRClientFoldingTests {

    private func makeClient() -> QwenRealtimeASRClient {
        let ws = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid")!)
        return QwenRealtimeASRClient(transport: ws)
    }

    @Test func partialPreviewIsTextPlusStash() async {
        let client = makeClient()
        #expect(await client.handleEvent(.partial(text: "你好", stash: "世")) == .partial(preview: "你好世"))
    }

    @Test func laterPartialReplacesPreview() async {
        let client = makeClient()
        _ = await client.handleEvent(.partial(text: "你好", stash: "世"))
        #expect(await client.handleEvent(.partial(text: "你好世界", stash: "")) == .partial(preview: "你好世界"))
    }

    @Test func completedBecomesFinalSourceOfTruth() async {
        let client = makeClient()
        _ = await client.handleEvent(.partial(text: "你好世", stash: "界"))
        #expect(await client.handleEvent(.completed(transcript: "你好世界，法言")) == .final(transcript: "你好世界，法言"))
        let transcript = await client.transcript
        #expect(transcript == "你好世界，法言")
    }

    @Test func failureBecomesFailed() async {
        let client = makeClient()
        #expect(await client.handleEvent(.failure("quota")) == .failed(message: "quota"))
    }

    @Test func ignoredYieldsNil() async {
        let client = makeClient()
        #expect(await client.handleEvent(.ignored) == nil)
    }
}
