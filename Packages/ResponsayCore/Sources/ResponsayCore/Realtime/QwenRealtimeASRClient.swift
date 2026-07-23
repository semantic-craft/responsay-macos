import Foundation

/// Drives qwen3-asr-flash-realtime over the OmniRealtime WebSocket in push-to-talk
/// (Manual) mode: `session.update` (turn_detection null) → `input_audio_buffer.append`
/// frames while the hotkey is held → `commit` on release → `...completed` transcript.
/// Mirrors `VolcengineRealtimeClient` so realtime engines
/// expose the same Plan-B `TranscriptUpdate` fold (partial → capsule, final → source of
/// truth). Unlike 火山's whole-clip replay this is built to be fed *live* frames.
///
/// `send*`/`receive` touch the live socket (mic + network) — the HITL boundary; the fold
/// and the wire codec are unit-tested offline.
public actor QwenRealtimeASRClient {
    private let transport: URLSessionWebSocketTask
    private var lastPreview = ""
    private var finalTranscript = ""

    public init(transport: URLSessionWebSocketTask) {
        self.transport = transport
    }

    // MARK: - Client → server

    public func sendSessionUpdate(language: String, sampleRate: Int = 16000, format: String = "pcm") async throws {
        try await send(QwenRealtimeASRProtocol.sessionUpdate(language: language, sampleRate: sampleRate, format: format))
    }

    public func sendAudio(_ pcm: Data) async throws {
        try await send(QwenRealtimeASRProtocol.appendAudio(pcm))
    }

    /// End the turn (Fn released) → the server produces the terminal transcript.
    public func commit() async throws {
        try await send(QwenRealtimeASRProtocol.commit())
    }

    private func send(_ data: Data) async throws {
        try await transport.send(.string(String(data: data, encoding: .utf8) ?? ""))
    }

    // MARK: - Server → client

    public func receive() async throws -> QwenRealtimeASRProtocol.ServerEvent {
        switch try await transport.receive() {
        case let .string(text):
            return QwenRealtimeASRProtocol.decode(Data(text.utf8))
        case let .data(data):
            return QwenRealtimeASRProtocol.decode(data)
        @unknown default:
            return .ignored
        }
    }

    /// Fold an event into a `TranscriptUpdate`. `text+stash` is the current cumulative
    /// hypothesis → replace the preview; `completed` is the final source of truth.
    public func handleEvent(_ event: QwenRealtimeASRProtocol.ServerEvent) -> TranscriptUpdate? {
        switch event {
        case let .partial(text, stash):
            lastPreview = text + stash
            return .partial(preview: lastPreview)
        case let .completed(transcript):
            finalTranscript = transcript
            return .final(transcript: transcript)
        case let .failure(message):
            return .failed(message: message.isEmpty ? nil : message)
        case .ignored:
            return nil
        }
    }

    public var transcript: String { finalTranscript.isEmpty ? lastPreview : finalTranscript }
}
