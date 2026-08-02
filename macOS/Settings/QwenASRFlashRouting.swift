import Foundation
import ResponsayCore

/// Endpoint/model resolution for the `qwen-asr-flash` ASR card, shared by the three readers of
/// the stored BYOK selection (`ProviderConfigMachine`, `ProviderConfigDispatcher`,
/// `ASRTranscriptionClientFactory`) so they cannot drift apart.
///
/// Two jobs:
/// 1. **Workspace derivation.** Filling in a Workspace ID switches the socket to that business
///    space's dedicated host; leaving it blank keeps the generic DashScope host, which the docs
///    state still works ("现有域名仍可正常使用").
/// 2. **Migration off the retired OmniRealtime endpoint.** This card used to front
///    `wss://dashscope.aliyuncs.com/api-ws/v1/**realtime**` with a `qwen3-asr-flash-realtime-*`
///    model — a different protocol on a sibling path, and the one Qwen realtime model that
///    supports no hotwords at all. Installs from ≤1.7.4 still have those values persisted under
///    these keys, so they are dropped in favour of the catalog defaults rather than dialled.
enum QwenASRFlashRouting {
    static let providerId = "qwen-asr-flash"

    /// The only realtime model that accepts 即时热词 (`vocabulary`); Fun-ASR-Realtime shares the
    /// protocol and endpoint but not that field, so it is offered as an alternative, not the default.
    static let defaultModel = QwenRunTaskEndpoint.defaultModel
    static let funASRRealtimeModel = "fun-asr-realtime"

    static let chinaBaseURL = QwenRunTaskEndpoint(region: .china).url.absoluteString
    static let singaporeBaseURL = QwenRunTaskEndpoint(region: .singapore).url.absoluteString

    /// The socket to dial. Fully derived from 接入点 + Workspace ID: the run-task path is fixed and
    /// the host is either the business space's or the region's, so there is nothing for a stored
    /// Base URL to contribute — which is also why the card shows this read-only. Any persisted
    /// OmniRealtime leftover is therefore ignored by construction rather than pattern-matched.
    static func endpoint(workspaceID: String?, region: ProviderRegion) -> QwenRunTaskEndpoint {
        QwenRunTaskEndpoint(region: runTaskRegion(region), workspaceID: workspaceID)
    }

    static func runTaskRegion(_ region: ProviderRegion) -> QwenRunTaskRegion {
        region == .singapore ? .singapore : .china
    }

    /// What the settings card and the lane display should show — the same URL the engine dials.
    static func displayBaseURL(workspaceID: String?, region: ProviderRegion) -> String {
        endpoint(workspaceID: workspaceID, region: region).url.absoluteString
    }

    /// Drop a persisted model id that belongs to a retired engine; keep any other user pick
    /// (the model, unlike the endpoint, IS selectable — streaming vs Fun-ASR-Realtime).
    static func normalizedModel(stored: String?, fallback: String) -> String {
        guard let stored = nonEmpty(stored), !isRetiredOmniRealtimeModel(stored) else { return fallback }
        return stored
    }

    /// `qwen3-asr-flash-realtime*` spoke the other protocol and supports no hotwords;
    /// `qwen-audio-3.0-asr-flash` (no `-streaming`) was the short-lived 非实时 HTTP model.
    private static func isRetiredOmniRealtimeModel(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.hasPrefix("qwen3-asr-flash-realtime") { return true }
        return lowered.hasPrefix("qwen-audio-3.0-asr-flash") && !lowered.contains("streaming")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
