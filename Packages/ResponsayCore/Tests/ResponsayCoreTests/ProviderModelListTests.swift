import Testing
import Foundation
@testable import ResponsayCore

/// Parses a provider's live `GET <base>/models` response so the Settings model
/// field can be populated from what the provider currently offers (instead of a
/// hard-coded id that goes stale). Mirrors openless `commands/providers.rs`:
/// OpenAI `{data:[{id}]}` + Google `{models:[{name,supportedGenerationMethods}]}`.
@Suite struct ProviderModelListTests {
    @Test func modelsURLAppendsModels() {
        #expect(ProviderModelList.modelsURL(base: "https://api.openai.com/v1")
            == "https://api.openai.com/v1/models")
    }

    @Test func modelsURLStripsChatCompletions() {
        #expect(ProviderModelList.modelsURL(base: "https://x/v1/chat/completions")
            == "https://x/v1/models")
    }

    @Test func modelsURLKeepsExistingModelsAndTrimsSlash() {
        #expect(ProviderModelList.modelsURL(base: "https://x/v1/models/") == "https://x/v1/models")
    }

    @Test func parsesOpenAIDataSortedAndDeduped() {
        let json = Data(#"{"data":[{"id":"whisper-1"},{"id":"gpt-4o-transcribe"},{"id":"whisper-1"}]}"#.utf8)
        #expect(ProviderModelList.parse(json, isGemini: false) == ["gpt-4o-transcribe", "whisper-1"])
    }

    @Test func parsesGeminiAndFiltersNonGenerateContent() {
        let json = Data(#"""
        {"models":[
          {"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent"]},
          {"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]}
        ]}
        """#.utf8)
        // Embedding model dropped; "models/" prefix stripped.
        #expect(ProviderModelList.parse(json, isGemini: true) == ["gemini-2.5-flash"])
    }

    @Test func geminiKeepsModelWhenMethodsFieldMissing() {
        // Conservative: a preview model that omits the field is still shown.
        let json = Data(#"{"models":[{"name":"models/gemini-preview"}]}"#.utf8)
        #expect(ProviderModelList.parse(json, isGemini: true) == ["gemini-preview"])
    }

    @Test func parseReturnsEmptyOnGarbage() {
        #expect(ProviderModelList.parse(Data("not json".utf8), isGemini: false).isEmpty)
        #expect(ProviderModelList.parse(Data(#"{"object":"list"}"#.utf8), isGemini: false).isEmpty)
    }

    @Test func asrModelsKeepsTranscriptionIDs() {
        let ids = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1", "gpt-5.5", "text-embedding-3"]
        #expect(ProviderModelList.asrModels(from: ids)
            == ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"])
    }

    @Test func asrModelsFallsBackToAllWhenNoKeywordMatches() {
        // Gemini's ASR is a general model with no ASR-ish id → don't hide everything.
        let ids = ["gemini-2.5-flash", "gemini-2.5-pro"]
        #expect(ProviderModelList.asrModels(from: ids) == ids)
    }

    @Test func isGeminiBaseDetectsGoogleHost() {
        #expect(ProviderModelList.isGeminiBase("https://generativelanguage.googleapis.com/v1beta"))
        #expect(!ProviderModelList.isGeminiBase("https://api.openai.com/v1"))
    }

    @Test func geminiOpenAICompatBaseIsNotNative() {
        // Bug fix: our Gemini preset uses the openai-compat base, which returns OpenAI `{data:[{id}]}`
        // shape — it must NOT be treated as Gemini-native, or Fetch-models parses the wrong key → [].
        let base = "https://generativelanguage.googleapis.com/v1beta/openai/"
        #expect(!ProviderModelList.isGeminiBase(base))
        let json = Data(#"{"data":[{"id":"models/gemini-3.5-flash"},{"id":"gemini-3.1-pro"}]}"#.utf8)
        // Parsed as OpenAI shape; a leftover `models/` prefix is stripped.
        #expect(ProviderModelList.parse(json, isGemini: ProviderModelList.isGeminiBase(base))
            == ["gemini-3.1-pro", "gemini-3.5-flash"])
    }
}
