import Testing
import Foundation
@testable import ResponsayCore

/// 129 — TTS provider catalog (core abstraction).
/// Verification: voice-by-model filter; default model/voice resolution; catalog decode.
struct TTSProviderCatalogTests {
    private func sampleCatalog() -> TTSProviderCatalog {
        TTSProviderCatalog(
            providerID: "qwen",
            displayName: "Qwen TTS",
            models: [
                TTSModelSpec(id: "qwen-tts", displayName: "Qwen TTS", supportsStreaming: true, supportsWordTiming: true),
                TTSModelSpec(id: "qwen-tts-lite", displayName: "Qwen TTS Lite"),
            ],
            voices: [
                TTSVoiceSpec(id: "cherry", displayName: "Cherry", supportedModelIDs: ["qwen-tts"]),
                TTSVoiceSpec(id: "ethan", displayName: "Ethan", supportedModelIDs: ["qwen-tts-lite"]),
                TTSVoiceSpec(id: "any", displayName: "Universal", supportedModelIDs: []),
            ],
            defaults: TTSDefaults(modelID: "qwen-tts", voiceID: "cherry")
        )
    }

    @Test func voicesFilteredByModel() {
        let catalog = sampleCatalog()
        let forMain = catalog.voices(forModel: "qwen-tts").map(\.id)
        #expect(forMain.contains("cherry"))
        #expect(forMain.contains("any"))          // model-agnostic voice
        #expect(forMain.contains("ethan") == false)
    }

    @Test func defaultModelAndVoiceResolve() {
        let catalog = sampleCatalog()
        #expect(catalog.defaultModel?.id == "qwen-tts")
        #expect(catalog.defaultVoice?.id == "cherry")
    }

    @Test func defaultVoice_nilWhenNotValidForDefaultModel() {
        var catalog = sampleCatalog()
        catalog.defaults = TTSDefaults(modelID: "qwen-tts", voiceID: "ethan") // ethan ∉ qwen-tts
        #expect(catalog.defaultVoice == nil)
    }

    @Test func catalogDecodesFromJSON() throws {
        let json = """
        {
          "providerID": "minimax", "displayName": "MiniMax",
          "models": [{"id":"speech-01","displayName":"Speech 01","supportsStreaming":true,
                      "supportsWordTiming":false,"supportsSentenceTiming":true,"supportsRealtimeWS":true}],
          "voices": [{"id":"v1","displayName":"V1","supportedModelIDs":["speech-01"],
                      "languageHints":["zh","en"],"styleTags":["calm"]}],
          "defaults": {"modelID":"speech-01","voiceID":"v1","speed":1.0,"sampleRate":24000}
        }
        """.data(using: .utf8)!
        let catalog = try JSONDecoder().decode(TTSProviderCatalog.self, from: json)
        #expect(catalog.providerID == "minimax")
        #expect(catalog.models.first?.supportsSentenceTiming == true)
        #expect(catalog.voices(forModel: "speech-01").count == 1)
        #expect(catalog.defaultModel?.id == "speech-01")
    }

    @Test func ttsKeyNamespace_distinctFromCoach() {
        #expect(TTSCredential.keychainAccount(for: "qwen") == "byok.tts.qwen")
        #expect(TTSCredential.coachAccount(for: "qwen") == "byok.qwen")
        #expect(TTSCredential.keychainAccount(for: "qwen") != TTSCredential.coachAccount(for: "qwen"))
    }
}
