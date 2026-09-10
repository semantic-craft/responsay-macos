import Foundation

/// Socket boundary used to test live upload and cancellation without a microphone or network.
protocol VolcengineRealtimeTransport: Sendable {
    func start()
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func cancel()
}

struct VolcengineURLSessionTransport: VolcengineRealtimeTransport {
    let task: URLSessionWebSocketTask
    func start() { task.resume() }
    func send(_ data: Data) async throws { try await task.send(.data(data)) }
    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: throw VolcengineRealtimeProtocol.Failure.badPayload
        }
    }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }
}
