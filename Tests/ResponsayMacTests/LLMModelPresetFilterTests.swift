import XCTest
import ResponsayCore
@testable import ResponsayMac

final class LLMModelPresetFilterTests: XCTestCase {
    /// A fetch is narrowed to qwen's curated LLM set, dropping the other ids its `/models`
    /// endpoint returns. qwen3.7-max is curated now (技能平台模型可选)，所以保留。
    /// Curated order is preserved.
    func testQwenLLMFetchNarrowsToCuratedModels() {
        let models = LLMModelPresetFilter.models(
            from: ["qwen3.6-flash", "qwen3.7-flash", "qwen3.7-max", "qwen-mt-turbo", "qwen3.6-plus", "qwen3.7-plus"],
            preset: ProviderCatalog.qwen,
            capability: .llm)

        XCTAssertEqual(models, ["qwen3.7-flash", "qwen3.7-max", "qwen3.6-flash", "qwen3.6-plus", "qwen3.7-plus"])
    }

    /// The Qwen PAYG default is part of the curated set, so it survives a fetch alongside the
    /// other curated ids that the provider list happens to include.
    func testQwenDefaultFlashStaysCuratedWhenFetched() {
        let models = LLMModelPresetFilter.models(
            from: ["qwen3.7-max", "qwen3.7-plus", "qwen3.6-flash", "qwen3.7-flash"],
            preset: ProviderCatalog.qwen,
            capability: .llm)

        XCTAssertEqual(models, ["qwen3.7-flash", "qwen3.7-max", "qwen3.6-flash", "qwen3.7-plus"])
    }

    func testLLMFetchFallsBackToCuratedDefaultWhenProviderListOmitsIt() {
        let models = LLMModelPresetFilter.models(
            from: ["deepseek-chat", "deepseek-reasoner"],
            preset: ProviderCatalog.deepseek,
            capability: .llm)

        XCTAssertEqual(models, ["deepseek-v4-flash"])
    }

    func testMiMoLLMDefaultAndPresetListStayOnV25NotLegacyFlash() {
        XCTAssertEqual(ProviderCatalog.mimo.defaultModels[.llm], "mimo-v2.5")

        let models = LLMModelPresetFilter.models(
            from: ["mimo-v2-flash", "MiMo-V2-Flash", "mimo-v2.5-pro"],
            preset: ProviderCatalog.mimo,
            capability: .llm)

        XCTAssertEqual(models, ["mimo-v2.5"])
    }

    /// Gemini (2026-06-16) — the LLM lane offers several current text models (more than the single
    /// flash-lite it shipped with), with flash-lite still first = the default. The list is text-only:
    /// no TTS/image/embedding/live id leaks in — Gemini TTS is a SEPARATE catalog, and the curated
    /// LLM list is the whitelist that keeps a /models fetch from mixing the two. Also a fetch that
    /// returns Gemini's full mixed catalog narrows to the curated text models.
    func testGeminiLLMListIsTextOnlyWithFlashLiteDefaultFirst() {
        let llm = ProviderCatalog.gemini.presetModels[.llm] ?? []
        XCTAssertEqual(llm.first, "gemini-3.5-flash-lite")
        XCTAssertEqual(ProviderCatalog.gemini.defaultModels[.llm], "gemini-3.5-flash-lite")
        XCTAssertTrue(llm.contains("gemini-3.5-flash"))
        XCTAssertTrue(llm.contains("gemini-3.1-flash-lite"))
        XCTAssertGreaterThan(llm.count, 1)
        for id in llm {
            for bad in ["tts", "image", "embedding", "-live", "veo", "lyria"] {
                XCTAssertFalse(id.contains(bad), "non-LLM id \(id) leaked into Gemini LLM list")
            }
        }
        // Gemini now ALSO offers TTS (single gemini-3.1-flash-tts-preview), but the two lanes stay
        // separate: the TTS model lives only in presetModels[.tts], never in the curated LLM list.
        XCTAssertTrue(ProviderCatalog.gemini.capabilities.contains(.tts))
        XCTAssertEqual(ProviderCatalog.gemini.presetModels[.tts], ["gemini-3.1-flash-tts-preview"])
        XCTAssertFalse((ProviderCatalog.gemini.presetModels[.llm] ?? []).contains { $0.contains("tts") })

        // A /models fetch returning Gemini's full mixed catalog narrows to the curated text models,
        // dropping the TTS/image ids it also returns.
        let narrowed = LLMModelPresetFilter.models(
            from: ["gemini-3.5-flash", "gemini-3.1-flash-tts-preview", "gemini-2.5-flash-image", "gemini-2.5-pro"],
            preset: ProviderCatalog.gemini,
            capability: .llm)
        XCTAssertEqual(narrowed, ["gemini-3.5-flash", "gemini-2.5-pro"])
    }

    /// MiniMax is TTS-only since 1.5.1 (the 423 LLM lane is retired): no LLM capability, no LLM
    /// models, absent from the LLM provider picker — while the TTS side stays fully intact.
    func testMiniMaxIsTTSOnly() {
        let preset = ProviderCatalog.minimax
        XCTAssertFalse(preset.capabilities.contains(.llm))
        XCTAssertNil(preset.defaultModels[.llm])
        XCTAssertNil(preset.presetModels[.llm])
        XCTAssertFalse(ProviderCatalog.presets(for: .llm).map(\.id).contains("minimax"))
        // TTS side is unchanged.
        XCTAssertTrue(preset.capabilities.contains(.tts))
        XCTAssertEqual(preset.defaultModels[.tts], "speech-2.8-hd")
        XCTAssertTrue(ProviderCatalog.presets(for: .tts).map(\.id).contains("minimax"))
    }

    func testCustomLLMFetchKeepsProviderList() {
        let fetched = ["custom-fast", "custom-max"]
        let models = LLMModelPresetFilter.models(
            from: fetched,
            preset: ProviderCatalog.custom,
            capability: .llm)

        XCTAssertEqual(models, fetched)
    }

    func testNonLLMFetchKeepsProviderList() {
        let fetched = ["speech-2.8-hd", "speech-2.8-turbo"]
        let models = LLMModelPresetFilter.models(
            from: fetched,
            preset: ProviderCatalog.minimax,
            capability: .tts)

        XCTAssertEqual(models, fetched)
    }

    /// When the fetched list already contains real transcription ids, ASR narrowing is a no-op:
    /// OpenAI keeps every transcription id its endpoint returns — including the un-curated
    /// `gpt-4o-mini-transcribe` — rather than being trimmed to the curated set.
    func testOpenAIASRFetchKeepsAllReturnedTranscriptionModels() {
        let fetched = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        let models = LLMModelPresetFilter.models(
            from: fetched,
            preset: ProviderCatalog.openAI,
            capability: .asr)

        XCTAssertEqual(models, ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"])
    }

    /// Gemini flash 是开放族（`openModelFamilies`）：比列表更新的一代 flash / flash-lite 一经发布，
    /// 「拉取模型」就能选到，不用等 App 更新。新的排在最前，越新越靠前；预设列表本身顺序不变。
    func testGeminiFetchSurfacesNewerFlashGenerationAheadOfCuratedList() {
        let models = LLMModelPresetFilter.models(
            from: ["gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-3.7-flash",
                   "gemini-3.7-flash-lite", "gemini-4-flash-preview", "gemini-2.5-pro"],
            preset: ProviderCatalog.gemini,
            capability: .llm)

        XCTAssertEqual(models, [
            "gemini-4-flash-preview", "gemini-3.7-flash", "gemini-3.7-flash-lite",
            "gemini-3.5-flash-lite", "gemini-3.5-flash", "gemini-2.5-pro",
        ])
    }

    /// The open family is shaped, not keyword-matched: a *newer* generation's image / tts / live /
    /// native-audio ids stay out of the text picker, and so does a newer Pro (a different family —
    /// curation still decides those).
    func testGeminiFetchKeepsNonTextAndOtherFamilyModelsOutEvenWhenNewer() {
        let models = LLMModelPresetFilter.models(
            from: ["gemini-3.5-flash-lite", "gemini-3.7-flash-image", "gemini-3.7-flash-tts-preview",
                   "gemini-live-3.7-flash-preview", "gemini-3.7-flash-preview-native-audio-dialog",
                   "gemini-3.7-pro-preview", "gemini-embedding-002"],
            preset: ProviderCatalog.gemini,
            capability: .llm)

        XCTAssertEqual(models, ["gemini-3.5-flash-lite"])
    }

    /// Discovery only reaches *forward*: older flash ids the curation deliberately left out are
    /// still left out, and a curated `*-latest` alias (no pinned version) does not count as
    /// "newest curated" — otherwise nothing could ever be newer and the family would be closed.
    func testGeminiFetchIgnoresOlderUncuratedFlashModels() {
        let models = LLMModelPresetFilter.models(
            from: ["gemini-2.0-flash", "gemini-2.0-flash-lite-001", "gemini-3.1-flash-lite",
                   "gemini-3.6-flash-lite", "gemini-flash-latest"],
            preset: ProviderCatalog.gemini,
            capability: .llm)

        XCTAssertEqual(models, ["gemini-3.6-flash-lite", "gemini-3.1-flash-lite", "gemini-flash-latest"])
    }

    /// The `*-latest` aliases are curated on both lanes, so 「一直用最新一代」 works even without a
    /// fetch — and the ASR lane opens the same flash family for dictation.
    func testGeminiLatestAliasesAreCuratedAndASRLaneOpensTheFlashFamily() {
        XCTAssertTrue((ProviderCatalog.gemini.presetModels[.llm] ?? []).contains("gemini-flash-lite-latest"))
        XCTAssertTrue((ProviderCatalog.gemini.presetModels[.asr] ?? []).contains("gemini-flash-lite-latest"))

        let models = LLMModelPresetFilter.models(
            from: ["gemini-3.1-flash-lite", "gemini-3.7-flash-lite", "gemini-3.7-flash-tts-preview"],
            preset: ProviderCatalog.gemini,
            capability: .asr)

        XCTAssertEqual(models, ["gemini-3.7-flash-lite", "gemini-3.1-flash-lite"])
    }

    /// A provider with no open family is unaffected: qwen's fetch stays trimmed to its curated set
    /// even when the endpoint offers a newer flash-shaped id.
    func testProviderWithoutOpenFamilyStaysCurated() {
        let models = LLMModelPresetFilter.models(
            from: ["qwen3.7-flash", "qwen3.9-flash"],
            preset: ProviderCatalog.qwen,
            capability: .llm)

        XCTAssertEqual(models, ["qwen3.7-flash"])
    }

    /// A custom OpenAI-compatible ASR endpoint has no curation, so its fetched list passes
    /// through untouched.
    func testCustomASRFetchKeepsProviderList() {
        let fetched = ["my-asr-large", "my-asr-fast"]
        let models = LLMModelPresetFilter.models(
            from: fetched,
            preset: ProviderCatalog.custom,
            capability: .asr)

        XCTAssertEqual(models, fetched)
    }

}
