import Foundation

public enum QwenRealtimeRegion: String, Sendable, CaseIterable {
    case china
    case singapore

    public var host: String {
        switch self {
        case .china:
            return "dashscope.aliyuncs.com"
        case .singapore:
            return "dashscope-intl.aliyuncs.com"
        }
    }
}

public struct QwenRealtimeEndpoint: Sendable, Equatable {
    public static let defaultModel = "qwen3-asr-flash-realtime-2026-02-10"

    public var model: String
    public var region: QwenRealtimeRegion
    public var includeBetaHeader: Bool

    public init(
        model: String = QwenRealtimeEndpoint.defaultModel,
        region: QwenRealtimeRegion = .china,
        includeBetaHeader: Bool = false
    ) {
        self.model = model
        self.region = region
        self.includeBetaHeader = includeBetaHeader
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.host
        // Qwen3-ASR realtime speaks the OpenAI-Realtime protocol (session.update /
        // input_audio_buffer.*), served at /api-ws/v1/realtime. The sibling
        // /api-ws/v1/inference path is the DashScope-native run-task protocol used
        // by fun-asr-realtime/paraformer only.
        components.path = "/api-ws/v1/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        return components.url!
    }
}
