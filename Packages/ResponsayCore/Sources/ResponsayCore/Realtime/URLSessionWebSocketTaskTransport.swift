import Foundation

public enum RealtimeTransportError: Error, LocalizedError, Sendable {
    case notConnected
    case nonUTF8Frame
    case unsupportedFrame

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Realtime WebSocket is not connected."
        case .nonUTF8Frame:
            return "Realtime WebSocket received a non-UTF8 frame."
        case .unsupportedFrame:
            return "Realtime WebSocket received an unsupported frame."
        }
    }
}

public actor URLSessionWebSocketTaskTransport: RealtimeTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL, bearerToken: String) {
        let task = session.webSocketTask(with: Self.makeRequest(url: url, bearerToken: bearerToken))
        self.task = task
        task.resume()
    }

    public func send(_ data: Data) async throws {
        guard let task else { throw RealtimeTransportError.notConnected }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeTransportError.nonUTF8Frame
        }
        try await task.send(.string(text))
    }

    public func receive() async throws -> Data {
        guard let task else { throw RealtimeTransportError.notConnected }
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return Data(text.utf8)
        case let .data(data):
            return data
        @unknown default:
            throw RealtimeTransportError.unsupportedFrame
        }
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    static func makeRequest(url: URL, bearerToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
