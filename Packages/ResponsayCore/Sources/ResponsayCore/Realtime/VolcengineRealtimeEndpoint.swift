import Foundation

/// The Volcengine streaming-input ASR endpoint (`bigmodel_nostream`, #580) and
/// its handshake auth headers. The streaming-INPUT mode recognizes the WHOLE utterance
/// semantically when the last packet arrives (~300–400ms for a 5s clip per the official
/// docs) — the bidirectional modes punctuate on pause acoustics, which shredded 口述释字
/// into mid-name sentence breaks. Our client is final-only anyway (it never consumed the
/// realtime characters), so this trades nothing. Unlike DashScope (Bearer token), ByteDance authenticates
/// the WebSocket upgrade with `X-Api-*` headers, so this builds a `URLRequest` directly
/// rather than reusing the Bearer-only `URLSessionWebSocketTaskTransport`. Uses the new
/// 语音控制台 single `X-Api-Key` — the same key slot the whole-clip 火山 engine
/// (`volcengine-flash`) already uses, so no second key entry.
public struct VolcengineRealtimeEndpoint: Sendable, Equatable {
    public var apiKey: String
    public var resourceID: String
    public var host: String
    public var path: String

    public init(
        apiKey: String,
        // 豆包流式语音识别 **2.0** 小时版. The 1.0 family (`volc.bigasr.sauc.*`) is 403 for
        // new-console keys; the 2.0 `seedasr` family matches the whole-clip 火山 engine's
        // `volc.seedasr.auc` grant, so the same X-Api-Key that works for batch also upgrades
        // here (verified: 1.0 → 403, 2.0 → 101). 并发版 users can pass `.concurrent`.
        resourceID: String = "volc.seedasr.sauc.duration",
        host: String = "openspeech.bytedance.com",
        path: String = "/api/v3/sauc/bigmodel_nostream"
    ) {
        self.apiKey = apiKey
        self.resourceID = resourceID
        self.host = host
        self.path = path
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = path
        return components.url!
    }

    /// `connectID` is a per-session UUID reused for both the connect and request IDs
    /// (matches the reference client); the server echoes an `X-Tt-Logid` back.
    public func makeRequest(connectID: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Request-Id")
        return request
    }
}
