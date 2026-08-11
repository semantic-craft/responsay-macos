import ResponsayCore

/// openless-aligned residency management on ASR engine-select
/// (`preload_local_asr_in_background` + release-on-switch, coordinator.rs):
///
/// - Selecting a **local in-process** engine prewarms it in the background so the first
///   hotkey isn't blocked by a multi-second model load (LATENCY-MODELLOAD-001).
/// - Any *other* resident local ASR engine is released, so switching frees its RAM instead of
///   leaving a 1GB+ model resident until the keep-alive timer expires.
/// - Selecting a **cloud** engine releases all resident local ASR engines.
@MainActor
enum ASRResidencyPrewarm {
    static func onSelection(_ raw: String, residency: LocalEngineResidency = .shared) {
        let targetID = residencyID(for: raw)
        for id in residency.residentIDs where id != targetID && allResidencyIDs.contains(id) {
            residency.unload(id)   // free the engine we're switching away from
        }
        if let targetID, residency.canControl(targetID) {
            residency.preloadInBackground(targetID)
        }
    }

    /// The residency id (== `LocalModelSpec.id`) backing an in-process ASR engine, or nil
    /// for cloud / non-resident engines.
    static func residencyID(for raw: String) -> String? {
        ASREngine(rawValue: raw)?.localModelSpec?.id
    }

    static var allResidencyIDs: Set<String> {
        Set(ASREngine.selectableCases.compactMap { $0.localModelSpec?.id })
    }
}
