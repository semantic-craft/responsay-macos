import Foundation
import Testing
@testable import ResponsayCore

@Suite struct URLSessionWebSocketTaskTransportTests {
    @Test func defaultEndpointPinsLatestSnapshot() {
        let endpoint = QwenRealtimeEndpoint()

        #expect(endpoint.model == "qwen3-asr-flash-realtime-2026-02-10")
        #expect(endpoint.model == QwenRealtimeEndpoint.defaultModel)
    }

    @Test func endpointBuildsDashScopeRealtimeURL() {
        let endpoint = QwenRealtimeEndpoint(
            model: "qwen3-asr-flash-realtime",
            region: .singapore)

        #expect(endpoint.url.absoluteString == "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime")
    }

    @Test func requestAddsBearerAndOmitsBetaHeaderByDefault() {
        let request = URLSessionWebSocketTaskTransport.makeRequest(
            endpoint: QwenRealtimeEndpoint(),
            bearerToken: "secret")

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == nil)
    }

    @Test func requestCanOptIntoBetaHeader() {
        let request = URLSessionWebSocketTaskTransport.makeRequest(
            endpoint: QwenRealtimeEndpoint(includeBetaHeader: true),
            bearerToken: "secret")

        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == "realtime=v1")
    }
}
