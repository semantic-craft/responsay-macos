import Foundation
import ResponsayCore

/// A naming family whose *newer* members a `/models` fetch may add on top of a preset's curated
/// list. Curation exists to keep a provider's mixed catalog (image / tts / live / embedding ids)
/// out of the text picker — but it also freezes the list at release time, so a model that ships
/// after the app can never be picked from the menu. An open family reopens exactly one lane:
/// fetched ids that match the family's *shape* and are newer than everything curated.
enum OpenModelFamily: Sendable {
    /// Gemini 文本 flash 档: `gemini-<版本>-flash[-lite][-preview][-日期/构建]`, plus the
    /// `gemini-flash-latest` / `gemini-flash-lite-latest` aliases that track whatever Google
    /// ships next. Matched by shape rather than by a `flash` keyword on purpose: the same
    /// catalog carries `gemini-2.5-flash-image`, `gemini-3.1-flash-tts-preview`,
    /// `gemini-live-2.5-flash-preview` and `…-native-audio-dialog`, none of which belong in a
    /// text (or dictation) model menu.
    case geminiFlash

    /// Whether a fetched id belongs to this family.
    func contains(_ id: String) -> Bool {
        switch self {
        case .geminiFlash:
            let pattern = #"^gemini-([0-9]+(\.[0-9]+)?-)?flash(-lite)?(-preview)?(-latest|-[0-9][0-9-]*)?$"#
            return id.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// Generation of a family id, for "is this newer than what we curated". Gemini versions the
    /// family decimally (2.0 → 2.5 → 3 → 3.1 → 3.5), so the number parses as one. The `*-latest`
    /// aliases pin to no version and always resolve to the newest → `infinity`.
    func generation(of id: String) -> Double {
        switch self {
        case .geminiFlash:
            guard let range = id.range(of: #"(?<=^gemini-)[0-9]+(\.[0-9]+)?"#, options: .regularExpression),
                  let version = Double(id[range])
            else { return .infinity }
            return version
        }
    }
}

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
///
/// On top of the curated set, a preset's `openModelFamilies` lets newer members of one naming
/// family through (Gemini flash / flash-lite), listed first — that is how a generation released
/// after the app still reaches the menu.
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
        let curatedList = availableCuratedModels.isEmpty ? curatedModels : availableCuratedModels
        guard let family = preset.openModelFamilies[capability] else { return curatedList }
        return newerFamilyModels(in: fetchedModels, family: family, curated: curatedModels) + curatedList
    }

    /// Fetched family members newer than every *pinned* curated version, newest first. Only newer
    /// ones: older uncurated members (`gemini-2.0-flash`, `gemini-1.5-flash-8b`…) are what the
    /// curation deliberately left out. Curated `*-latest` aliases are ignored when measuring "the
    /// newest curated version" — they float to whatever ships next, so counting them as infinitely
    /// new would close the family again.
    private static func newerFamilyModels(
        in fetchedModels: [String],
        family: OpenModelFamily,
        curated: [String]
    ) -> [String] {
        let newestCurated = curated
            .filter(family.contains)
            .map(family.generation(of:))
            .filter(\.isFinite)
            .max() ?? 0
        let curatedSet = Set(curated)
        return fetchedModels
            .filter { family.contains($0) && !curatedSet.contains($0) }
            .filter { family.generation(of: $0) > newestCurated }
            .sorted { lhs, rhs in
                let (l, r) = (family.generation(of: lhs), family.generation(of: rhs))
                return l == r ? lhs < rhs : l > r
            }
    }
}
