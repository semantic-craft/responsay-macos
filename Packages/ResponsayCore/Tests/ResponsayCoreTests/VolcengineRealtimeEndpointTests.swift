import Foundation
import Testing
@testable import ResponsayCore

@Suite("Volcengine realtime endpoint")
struct VolcengineRealtimeEndpointTests {

    @Test func buildsBigmodelAsyncURL() {
        let endpoint = VolcengineRealtimeEndpoint(apiKey: "sk")
        #expect(endpoint.url.absoluteString ==
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
    }

    @Test func requestCarriesAuthHeaders() {
        // Override with a non-default (并发版) id to prove pass-through.
        let endpoint = VolcengineRealtimeEndpoint(
            apiKey: "sk-456", resourceID: "volc.seedasr.sauc.concurrent")
        let request = endpoint.makeRequest(connectID: "conn-789")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "sk-456")
        #expect(request.value(forHTTPHeaderField: "X-Api-Resource-Id") == "volc.seedasr.sauc.concurrent")
        #expect(request.value(forHTTPHeaderField: "X-Api-Connect-Id") == "conn-789")
        #expect(request.value(forHTTPHeaderField: "X-Api-Request-Id") == "conn-789")
    }

    /// Regression guard for the 403 bug: the default must be the 豆包流式 **2.0** (`seedasr`)
    /// 小时版 resource — the 1.0 `volc.bigasr.sauc.duration` is 403 for new-console keys.
    @Test func defaultResourceIDIsStreamingSeedASR2() {
        let endpoint = VolcengineRealtimeEndpoint(apiKey: "sk")
        #expect(endpoint.makeRequest(connectID: "c")
            .value(forHTTPHeaderField: "X-Api-Resource-Id") == "volc.seedasr.sauc.duration")
    }
}
