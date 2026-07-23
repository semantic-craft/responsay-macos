import Foundation
import ResponsayCore

/// Despite the legacy name (the Qwen realtime *engine* retired in 289),
/// this still picks the DashScope china/intl host for Qwen streaming TTS.
enum RealtimeQwenSettings {
    static let regionKey = "qwenRealtimeRegion"
}
