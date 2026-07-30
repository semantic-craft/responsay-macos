import Foundation

/// Turns one SSE line into a `TextStreamEvent`, or `nil` to skip it (blank lines, `:` keep-alives,
/// content-free frames, usage-only chunks). The **seam** between the shared `SSEStreamTransport` and
/// each provider's frame shape — two adapters today: `OpenAIStreamLineParser` (chat `choices[].delta`)
/// and `ArkResponsesStreamLineParser` (the shared Responses event shape). Pure; must be `Sendable`.
public protocol TextStreamEventParser: Sendable {
    func event(for line: String) -> TextStreamEvent?
}
