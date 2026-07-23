import Foundation
import Testing
@testable import ResponsayCore

/// Volcengine sends the *cumulative* transcript in every packet, so folding is a
/// straight replace: each `.response` becomes the current preview, and the
/// LAST_PACKET response becomes the final source-of-truth transcript. This mirrors
/// the shared Plan-B contract (`TranscriptUpdate`) already
/// satisfies, so both engines feed the capsule/skills identically.
@Suite("VolcengineRealtimeClient folding")
struct VolcengineRealtimeClientFoldingTests {

    private func makeClient() -> VolcengineRealtimeClient {
        let ws = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid")!)
        return VolcengineRealtimeClient(transport: ws)
    }

    @Test func partialResponseBecomesPreview() async {
        let client = makeClient()
        let update = await client.handleEvent(.response(text: "你好", isDefinite: false, isLast: false))
        #expect(update == .partial(preview: "你好"))
    }

    @Test func cumulativeTextReplacesPreview() async {
        let client = makeClient()
        _ = await client.handleEvent(.response(text: "你好", isDefinite: false, isLast: false))
        let update = await client.handleEvent(.response(text: "你好世界", isDefinite: true, isLast: false))
        #expect(update == .partial(preview: "你好世界"))
    }

    @Test func lastPacketBecomesFinal() async {
        let client = makeClient()
        _ = await client.handleEvent(.response(text: "你好世界", isDefinite: true, isLast: false))
        let update = await client.handleEvent(.response(text: "你好世界，法言", isDefinite: true, isLast: true))
        #expect(update == .final(transcript: "你好世界，法言"))
        let transcript = await client.transcript
        #expect(transcript == "你好世界，法言")
    }

    @Test func errorBecomesFailed() async {
        let client = makeClient()
        let update = await client.handleEvent(.error(code: 45000001, message: "quota exceeded"))
        #expect(update == .failed(message: "quota exceeded"))
    }
}
