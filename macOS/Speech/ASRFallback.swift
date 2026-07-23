import Foundation

/// Always-usable fallback for the ASR lane (#389, spec §6).
///
/// The app must never hard-fail capture because the *selected* engine isn't usable:
/// a cloud engine without a BYOK key, or an offline engine whose model hasn't been
/// downloaded. In those cases capture transiently falls back to **Apple** (zero-config,
/// on-device, always available) — without mutating the user's stored selection, so it
/// recovers automatically once the key is entered or the model finishes downloading.
enum ASRFallback {
    /// The downloadable model backing an offline engine, or nil for cloud / Apple.
    static func offlineSpec(for engine: ASREngine) -> LocalModelSpec? {
        switch engine {
        case .sensevoiceLocal: return .senseVoiceSmall
        case .qwen3LocalASR: return .qwen3ASR
        case .fireRedASR2AEDLocal: return .fireRedASR2AED
        case .funAsrNanoLocal: return .funAsrNano
        default: return nil
        }
    }

    /// Can this engine run right now? Apple always; an offline engine iff its model
    /// is installed; a cloud engine iff a BYOK key exists for its provider.
    static func isReady(
        _ engine: ASREngine,
        isInstalled: (LocalModelSpec) -> Bool = { $0.isInstalled },
        cloudHasKey: (ASREngine) -> Bool = { ModelLaneReadinessResolver().asr(optionId: $0.rawValue).isReady }
    ) -> Bool {
        if engine == .apple { return true }
        if let spec = offlineSpec(for: engine) { return isInstalled(spec) }
        return cloudHasKey(engine)
    }

    /// The engine to actually use: the selection if ready, else Apple. Transient —
    /// never mutates the stored selection.
    static func effectiveEngine(
        _ selected: ASREngine,
        isInstalled: (LocalModelSpec) -> Bool = { $0.isInstalled },
        cloudHasKey: (ASREngine) -> Bool = { ModelLaneReadinessResolver().asr(optionId: $0.rawValue).isReady }
    ) -> ASREngine {
        isReady(selected, isInstalled: isInstalled, cloudHasKey: cloudHasKey) ? selected : .apple
    }
}
