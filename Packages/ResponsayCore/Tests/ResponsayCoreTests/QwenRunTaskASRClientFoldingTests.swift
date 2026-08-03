import Foundation
import Testing
@testable import ResponsayCore

/// The run-task protocol delivers results **per sentence**, not as one cumulative hypothesis the
/// way the retired OmniRealtime engine did. So the fold has to accumulate finals across sentences
/// and still produce one 整段 transcript at `task-finished` — that assembly is what these tests pin,
/// along with the `task-started` gate that keeps the sender (and therefore `stop()`) from wedging.
@Suite("QwenRunTaskASRClient folding")
struct QwenRunTaskASRClientFoldingTests {

    /// The socket is never resumed — `handleEvent`/`transcript`/`awaitStarted` never touch it.
    private func makeClient() -> QwenRunTaskASRClient {
        let ws = URLSession.shared.webSocketTask(with: URL(string: "wss://example.invalid")!)
        return QwenRunTaskASRClient(transport: ws, taskID: "task-1")
    }

    @Test func intermediateSentenceBecomesPartialPreview() async {
        let client = makeClient()
        #expect(await client.handleEvent(.sentence(id: 1, text: "好，我知", isFinal: false))
                == .partial(preview: "好，我知"))
    }

    @Test func finalSentenceReplacesItsOwnIntermediate() async {
        let client = makeClient()
        _ = await client.handleEvent(.sentence(id: 1, text: "好，我知", isFinal: false))
        _ = await client.handleEvent(.sentence(id: 1, text: "好，我知道了", isFinal: true))
        #expect(await client.transcript == "好，我知道了")
    }

    /// Several VAD sentences over one hotkey press must join into a single 整段 transcript.
    @Test func multipleSentencesJoinIntoOneTranscript() async {
        let client = makeClient()
        _ = await client.handleEvent(.sentence(id: 1, text: "你好世界。", isFinal: true))
        _ = await client.handleEvent(.sentence(id: 2, text: "这是法言。", isFinal: true))
        #expect(await client.handleEvent(.finished) == .final(transcript: "你好世界。这是法言。"))
    }

    /// A replayed/duplicate final for the same `sentence_id` must not append twice.
    @Test func duplicateFinalForSameSentenceIDDoesNotDouble() async {
        let client = makeClient()
        _ = await client.handleEvent(.sentence(id: 1, text: "你好世界。", isFinal: true))
        _ = await client.handleEvent(.sentence(id: 1, text: "你好世界。", isFinal: true))
        #expect(await client.transcript == "你好世界。")
    }

    /// If the task ends while a sentence is still open, its text must survive rather than be lost.
    @Test func trailingOpenSentenceStillReachesTheFinalTranscript() async {
        let client = makeClient()
        _ = await client.handleEvent(.sentence(id: 1, text: "你好世界。", isFinal: true))
        _ = await client.handleEvent(.sentence(id: 2, text: "这是法言", isFinal: false))
        #expect(await client.handleEvent(.finished) == .final(transcript: "你好世界。这是法言"))
    }

    @Test func failureBecomesFailed() async {
        let client = makeClient()
        #expect(await client.handleEvent(.failure("CLIENT_ERROR: quota"))
                == .failed(message: "CLIENT_ERROR: quota"))
    }

    @Test func startedAndIgnoredProduceNoUpdate() async {
        let client = makeClient()
        #expect(await client.handleEvent(.started) == nil)
        #expect(await client.handleEvent(.ignored) == nil)
    }

    // MARK: - task-started gate

    /// Audio may not be sent before `task-started`; the sender awaits this gate.
    @Test func awaitStartedResolvesTrueOnceTaskStarts() async {
        let client = makeClient()
        async let gate = client.awaitStarted()
        _ = await client.handleEvent(.started)
        #expect(await gate)
        // Already started → subsequent waiters return immediately.
        #expect(await client.awaitStarted())
    }

    /// A handshake failure must release the gate too, or the sender task — and with it `stop()` —
    /// would hang forever waiting for a start that never comes.
    @Test func awaitStartedResolvesFalseWhenTheTaskFailsFirst() async {
        let client = makeClient()
        async let gate = client.awaitStarted()
        _ = await client.handleEvent(.failure("CLIENT_ERROR: bad key"))
        #expect(await gate == false)
        #expect(await client.awaitStarted() == false)
    }

    @Test func awaitStartedResolvesFalseWhenTheTaskFinishesFirst() async {
        let client = makeClient()
        async let gate = client.awaitStarted()
        _ = await client.handleEvent(.finished)
        #expect(await gate == false)
    }

    @Test func cancellingAwaitStartedReleasesTheWaiter() async {
        let client = makeClient()
        let gate = Task { await client.awaitStarted() }
        gate.cancel()
        #expect(await gate.value == false)
    }
}
