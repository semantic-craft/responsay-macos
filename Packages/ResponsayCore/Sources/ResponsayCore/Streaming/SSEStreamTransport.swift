import Foundation

/// The one deep module behind every `/chat/completions`- and `/responses`-style SSE stream.
///
/// Owns the whole transport: the `URLSession.bytes` fetch, the non-2xx HTTP gate (drained into
/// `LLMError.http`), the newline-framed byte loop, the terminal-event short-circuit (stop on the first
/// non-`.delta`), the trailing-line flush, task-cancellation teardown, and the error funnel. Callers
/// supply only what varies: a throwing `makeRequest` (URL + body + headers + timeout) and a
/// `TextStreamEventParser`. Nothing about the byte loop is duplicated per provider — one interface,
/// N request-builders (`DirectStreamingChatClient`, `DirectArkResponsesStreamingClient`, …).
public struct SSEStreamTransport: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Stream `TextStreamEvent`s from the request built by `makeRequest`, decoded by `parser`.
    /// `makeRequest` runs inside the streaming task, so its throws (e.g. `.notConfigured`,
    /// `.invalidEndpoint`, JSON encoding failures) surface as the stream's terminal error.
    public func stream(
        parser: any TextStreamEventParser,
        makeRequest: @escaping @Sendable () throws -> URLRequest
    ) -> AsyncThrowingStream<TextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session] in
                do {
                    let request = try makeRequest()
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let errorBody = String(decoding: try await bytes.reduce(into: [UInt8]()) { $0.append($1) }, as: UTF8.self)
                        continuation.finish(throwing: LLMError.http(status: code, body: errorBody))
                        return
                    }

                    var lineBuffer = [UInt8]()
                    for try await byte in bytes {
                        if byte != 0x0A { lineBuffer.append(byte); continue }
                        let line = String(decoding: lineBuffer, as: UTF8.self)
                        lineBuffer.removeAll(keepingCapacity: true)
                        guard let event = parser.event(for: line) else { continue }
                        continuation.yield(event)
                        if case .delta = event { continue }
                        continuation.finish()
                        return
                    }
                    if !lineBuffer.isEmpty,
                       let event = parser.event(for: String(decoding: lineBuffer, as: UTF8.self)) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
