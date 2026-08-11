import Foundation

enum QwenRunTaskTransportMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
}

/// The run-task session's one transport seam. Production uses URLSession; tests provide
/// deterministic scripted adapters that speak the same text/binary frame interface.
protocol QwenRunTaskTransport: Sendable {
    var isViable: Bool { get async }
    func send(_ message: QwenRunTaskTransportMessage) async throws
    func receive() async throws -> QwenRunTaskTransportMessage
    func close() async
}

final class QwenURLSessionWebSocketTransport: QwenRunTaskTransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask, resume: Bool = false) {
        self.task = task
        if resume { task.resume() }
    }

    var isViable: Bool {
        get async { task.state == .running }
    }

    func send(_ message: QwenRunTaskTransportMessage) async throws {
        switch message {
        case let .text(text):
            try await task.send(.string(text))
        case let .data(data):
            try await task.send(.data(data))
        }
    }

    func receive() async throws -> QwenRunTaskTransportMessage {
        switch try await task.receive() {
        case let .string(text): return .text(text)
        case let .data(data): return .data(data)
        @unknown default: throw RealtimeTransportError.unsupportedFrame
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
