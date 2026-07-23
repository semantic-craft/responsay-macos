import Foundation
import ResponsayCore

struct QwenAudioTTSEndpoint: Sendable, Equatable {
    let region: QwenRealtimeRegion

    init(region: QwenRealtimeRegion = .china) {
        self.region = region
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.host
        components.path = "/api-ws/v1/inference"
        return components.url!
    }
}
