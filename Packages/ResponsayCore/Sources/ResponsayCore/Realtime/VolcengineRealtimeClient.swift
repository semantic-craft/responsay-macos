import Foundation

/// Drives the Volcengine 大模型流式 ASR duplex protocol: full-client-request →
/// streamed audio frames → an empty LAST_PACKET frame, receiving cumulative
/// transcript responses. Mirrors the other realtime clients so all engines
/// expose the same Plan-B contract: `handleEvent` folds server frames into
/// `TranscriptUpdate` (`.partial` → capsule preview, `.final` → source of truth for
/// skills + insertion).
///
/// `send*`/`receive` touch the live socket (mic + network) and are the HITL boundary;
/// the fold in `handleEvent` and the wire codec are unit-tested offline.
public actor VolcengineRealtimeClient {
    private let transport: URLSessionWebSocketTask
    /// Volcengine resends the whole transcript each packet, so state is a single
    /// cumulative string (no per-sentence map like Fun-ASR).
    private var cumulativeText = ""

    public init(transport: URLSessionWebSocketTask) {
        self.transport = transport
    }

    // MARK: - Client → server

    public func sendFullClientRequest(config: VolcengineRealtimeConfig) async throws {
        try await transport.send(.data(VolcengineRealtimeProtocol.fullClientRequest(config: config)))
    }

    public func sendAudio(_ pcm: Data) async throws {
        try await transport.send(.data(VolcengineRealtimeProtocol.audioFrame(pcm, isLast: false)))
    }

    /// End-of-input: an empty audio frame with the LAST_PACKET flag.
    public func sendFinish() async throws {
        try await transport.send(.data(VolcengineRealtimeProtocol.audioFrame(Data(), isLast: true)))
    }

    // MARK: - Server → client

    public func receive() async throws -> VolcengineRealtimeProtocol.ServerMessage {
        let message = try await transport.receive()
        switch message {
        case let .data(data):
            return try VolcengineRealtimeProtocol.parse(data)
        case let .string(text):
            return try VolcengineRealtimeProtocol.parse(Data(text.utf8))
        @unknown default:
            throw VolcengineRealtimeProtocol.Failure.badPayload
        }
    }

    /// Fold a decoded frame into a `TranscriptUpdate`. Cumulative text → replace.
    public func handleEvent(_ message: VolcengineRealtimeProtocol.ServerMessage) -> TranscriptUpdate? {
        switch message {
        case let .response(text, _, isLast):
            cumulativeText = text
            return isLast ? .final(transcript: text) : .partial(preview: text)
        case let .error(_, message):
            return .failed(message: message.isEmpty ? nil : message)
        }
    }

    public var transcript: String { cumulativeText }
}
