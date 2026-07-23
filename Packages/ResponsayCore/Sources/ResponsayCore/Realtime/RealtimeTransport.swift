import Foundation

/// A bidirectional channel to the realtime ASR service.
///
/// Abstracts the WebSocket so the client's framing/orchestration logic can be
/// driven without a live socket. The production implementation wraps
/// `URLSessionWebSocketTask`; tests inject a recording double.
public protocol RealtimeTransport: Sendable {
    /// Send one serialised client-event frame.
    func send(_ data: Data) async throws
}
