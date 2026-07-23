import Foundation
import ResponsayCore

/// Narrows a fetched `GET /models` list to a preset's curated models, so a provider whose
/// endpoint advertises the *wrong* capability's models doesn't leak them into the card.
///
/// - LLM: narrow to `presetModels[.llm]`, falling back to the capability default — every LLM
///   provider has a sensible default, so the list is always trimmed to the curated set.
/// - ASR: keep the fetched list whenever it already contains a real transcription id (matched
///   by `ProviderModelList.looksLikeASR`), so providers surface every transcription id their
///   endpoint returns. If a provider explicitly curates ASR models and the fetched endpoint
///   returns no ASR-looking ids, use that curated list instead. Providers with no ASR curation
///   keep their fetched list.
/// - TTS: pass through (the TTS card drives its model menu from `presetModels`/`presetVoices`,
///   not from a `/models` fetch).
/// - Custom endpoints: always pass through — nothing is curated.
enum LLMModelPresetFilter {
    static func models(
        from fetchedModels: [String],
        preset: ProviderPreset,
        capability: ModelCapability
    ) -> [String] {
        guard !preset.isCustom else { return fetchedModels }
        let curatedModels: [String]
        switch capability {
        case .llm:
            curatedModels = preset.presetModels[.llm] ?? preset.defaultModels[.llm].map { [$0] } ?? []
        case .asr:
            if fetchedModels.contains(where: ProviderModelList.looksLikeASR) {
                return fetchedModels
            }
            curatedModels = preset.presetModels[.asr] ?? []
        case .tts:
            return fetchedModels
        }
        guard !curatedModels.isEmpty else { return fetchedModels }

        let fetched = Set(fetchedModels)
        let availableCuratedModels = curatedModels.filter { fetched.contains($0) }
        return availableCuratedModels.isEmpty ? curatedModels : availableCuratedModels
    }
}
