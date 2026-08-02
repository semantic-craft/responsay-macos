import Foundation
import ResponsayCore

/// Qwen-Audio-TTS shares the run-task WebSocket protocol, path and hosts with 实时语音识别 —
/// hence the shared `QwenRunTaskRegion` (raw values unchanged, so the stored 区域 setting carries
/// over). Workspace-dedicated hosts are not wired for TTS; it stays on the generic host.
struct QwenAudioTTSEndpoint: Sendable, Equatable {
    let region: QwenRunTaskRegion

    init(region: QwenRunTaskRegion = .china) {
        self.region = region
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = region.genericHost
        components.path = QwenRunTaskEndpoint.path
        return components.url!
    }
}
