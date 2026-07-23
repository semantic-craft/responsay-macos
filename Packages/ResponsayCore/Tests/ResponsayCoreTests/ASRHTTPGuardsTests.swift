import Testing
import Foundation
@testable import ResponsayCore

/// #2 ASR provider seam: the HTTP guards every cloud transcription provider repeated — audio-size,
/// status-validation, empty-result — extracted into one brand-parameterized helper, with the
/// byte-identical user-facing errors preserved.
struct ASRHTTPGuardsTests {
    private func message(of error: Error) -> String? {
        if case let CoachAPIError.message(m) = error { return m }
        return nil
    }

    @Test func audioSize_overCap_throwsTheSharedTooLongError() {
        do {
            try ASRHTTPGuards.audioSize(Data(count: 11), max: 10)
            Issue.record("expected throw")
        } catch {
            #expect(message(of: error) == "录音太长，请缩短后再试。")
        }
    }

    @Test func audioSize_withinCap_isANoOp() throws {
        try ASRHTTPGuards.audioSize(Data(count: 10), max: 10)  // no throw
    }

    private let url = URL(string: "https://example.com")!

    @Test func validate_nonHTTPResponse_throwsBrandedNetworkError() {
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        do {
            _ = try ASRHTTPGuards.validate(response, data: Data(), brand: "OpenAI ASR")
            Issue.record("expected throw")
        } catch {
            #expect(message(of: error) == "OpenAI ASR 网络错误")
        }
    }

    @Test func validate_non2xx_throwsBrandedStatusWithTruncatedBody() {
        let http = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let body = Data("nope".utf8)
        do {
            _ = try ASRHTTPGuards.validate(http, data: body, brand: "Gemini ASR")
            Issue.record("expected throw")
        } catch {
            #expect(message(of: error) == "Gemini ASR 404: nope")
        }
    }

    @Test func validate_2xx_returnsTheResponse() throws {
        let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let validated = try ASRHTTPGuards.validate(http, data: Data(), brand: "OpenAI ASR")
        #expect(validated.statusCode == 200)
    }

    @Test func nonEmpty_emptyTranscript_throwsBrandedEmptyError() {
        do {
            _ = try ASRHTTPGuards.nonEmpty("", brand: "火山引擎极速 ASR")
            Issue.record("expected throw")
        } catch {
            #expect(message(of: error) == "火山引擎极速 ASR 返回为空")
        }
    }

    @Test func nonEmpty_presentTranscript_returnsIt() throws {
        #expect(try ASRHTTPGuards.nonEmpty("hello", brand: "OpenAI ASR") == "hello")
    }
}
