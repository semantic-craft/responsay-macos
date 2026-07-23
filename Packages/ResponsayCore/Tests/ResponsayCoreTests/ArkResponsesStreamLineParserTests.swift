import Testing
@testable import ResponsayCore

struct ArkResponsesStreamLineParserTests {
    let parser = ArkResponsesStreamLineParser()

    @Test func textDeltaYieldsContent() {
        let line = #"data: {"type":"response.output_text.delta","delta":"你好"}"#
        #expect(parser.event(for: line) == .delta("你好"))
    }

    @Test func emptyDeltaIsIgnored() {
        let line = #"data: {"type":"response.output_text.delta","delta":""}"#
        #expect(parser.event(for: line) == nil)
    }

    @Test func completedTerminatesStream() {
        let line = #"data: {"type":"response.completed","response":{"status":"completed"}}"#
        #expect(parser.event(for: line) == .done)
    }

    @Test func incompleteTerminatesStream() {
        let line = #"data: {"type":"response.incomplete","response":{"status":"incomplete"}}"#
        #expect(parser.event(for: line) == .done)
    }

    @Test func doneSentinelTerminates() {
        #expect(parser.event(for: "data: [DONE]") == .done)
    }

    @Test func failedSurfacesNestedErrorMessage() {
        let line = #"data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"boom"}}}"#
        #expect(parser.event(for: line) == .failed("boom"))
    }

    @Test func scaffoldingEventsAreIgnored() {
        for type in ["response.created", "response.in_progress", "response.output_item.added",
                     "response.content_part.added", "response.reasoning_summary_text.delta",
                     "response.output_text.done"] {
            let line = "data: {\"type\":\"\(type)\"}"
            #expect(parser.event(for: line) == nil, "expected nil for \(type)")
        }
    }

    @Test func nonDataLinesAndKeepalivesAreIgnored() {
        #expect(parser.event(for: "event: response.output_text.delta") == nil)
        #expect(parser.event(for: ": keep-alive") == nil)
        #expect(parser.event(for: "") == nil)
    }

    /// A realistic frame order: scaffolding → deltas → terminal. Mirrors how the streaming client
    /// consumes lines (delta → keep going; first non-delta event → finish).
    @Test func realisticSequenceProducesDeltasThenDone() {
        let lines = [
            #"data: {"type":"response.created"}"#,
            #"data: {"type":"response.output_item.added"}"#,
            #"data: {"type":"response.output_text.delta","delta":"北京"}"#,
            #"data: {"type":"response.output_text.delta","delta":"今天晴"}"#,
            #"data: {"type":"response.output_text.done","text":"北京今天晴"}"#,
            #"data: {"type":"response.completed","response":{"status":"completed"}}"#,
        ]
        let events = lines.compactMap { parser.event(for: $0) }
        #expect(events == [.delta("北京"), .delta("今天晴"), .done])
    }
}
