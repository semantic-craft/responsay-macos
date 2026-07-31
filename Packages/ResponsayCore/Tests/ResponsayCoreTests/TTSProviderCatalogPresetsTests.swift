import Testing
import Foundation
@testable import ResponsayCore

/// 196 — cloud TTS provider catalog data. Test standard T1.
struct TTSProviderCatalogPresetsTests {
    @Test func everyCatalogResolvesItsDefaults() {
        for catalog in TTSProviderCatalogPresets.all {
            #expect(!catalog.voices.isEmpty)
            #expect(!catalog.models.isEmpty)
            #expect(catalog.defaultModel != nil, "\(catalog.providerID) default model dangles")
            #expect(catalog.defaultVoice != nil, "\(catalog.providerID) default voice dangles")
        }
    }

    @Test func lookupByProviderID() {
        #expect(TTSProviderCatalogPresets.catalog(for: "openai")?.providerID == "openai")
        #expect(TTSProviderCatalogPresets.catalog(for: "qwen")?.providerID == "qwen")
        #expect(TTSProviderCatalogPresets.catalog(for: "volcengine-tts")?.providerID == "volcengine-tts")
        #expect(TTSProviderCatalogPresets.catalog(for: "minimax")?.providerID == "minimax")
        #expect(TTSProviderCatalogPresets.catalog(for: "nope") == nil)
    }

    @Test func codableRoundTrip() throws {
        let catalog = TTSProviderCatalogPresets.qwen
        let decoded = try JSONDecoder().decode(
            TTSProviderCatalog.self, from: JSONEncoder().encode(catalog))
        #expect(decoded == catalog)
    }

    @Test func qwenExposesOnlyAudio3FlashAndItsCurrentVoices() {
        let catalog = TTSProviderCatalogPresets.qwen
        let ids = Set(catalog.voices.map(\.id))

        #expect(catalog.models.map(\.id) == ["qwen-audio-3.0-tts-flash"])
        #expect(catalog.defaults.modelID == "qwen-audio-3.0-tts-flash")
        #expect(catalog.defaults.voiceID == "loongeva_v3.6")
        #expect(catalog.defaultModel?.supportsRealtimeWS == true)
        for required in ["loongeva_v3.6", "loongjohn", "longanhuan_v3.6", "longjielidou_v3.6"] {
            #expect(ids.contains(required), "missing Qwen voice \(required)")
        }
    }

    @Test func minimaxVoicesCoverOfficialMultilingualPreset() {
        let voices = TTSProviderCatalogPresets.minimax.voices
        let ids = Set(voices.map(\.id))

        for required in [
            "English_Trustworthy_Man", "English_Graceful_Lady",
            "German_FriendlyMan", "German_SweetLady",
            "French_Male_Speech_New", "French_MovieLeadFemale",
            "Japanese_IntellectualSenior", "Japanese_DecisivePrincess",
            "Korean_SweetGirl", "Korean_CheerfulBoyfriend",
            // 设置卡「音色」菜单提供、而 catalog 一度漏掉的四项:TTSEngine.selectedVoiceID 拿
            // catalog.voices 校验用户的选择,漏掉就等于用户选了也被静默换回 male-qn-qingse。
            // macOS 端的全量交叉校验在 TTSEngineTests,但 CI 只跑 ResponsayCore,故在此钉死。
            "male-qn-jingying", "female-yujie", "Sweet_Girl", "Attractive_Girl",
        ] {
            #expect(ids.contains(required), "missing MiniMax voice \(required)")
        }
        #expect(voices.filter { $0.languageHints.contains("de") }.count >= 2)
        #expect(voices.filter { $0.languageHints.contains("en") }.count >= 2)
        #expect(voices.filter { $0.languageHints.contains("zh") }.count >= 2)
    }

    @Test func noProviderClaimsWordTiming() {
        // None of the surveyed cloud TTS APIs return word timing → highlight uses the
        // proportional aligner. Guard against a future preset over-promising.
        for catalog in TTSProviderCatalogPresets.all {
            for model in catalog.models {
                #expect(!model.supportsWordTiming, "\(catalog.providerID)/\(model.id)")
            }
        }
    }

    @Test func onlyQwenAdvertisesRealtimeStreaming() {
        let streaming = TTSProviderCatalogPresets.all
            .filter { $0.models.contains { $0.supportsRealtimeWS } }
            .map(\.providerID)
        #expect(streaming == ["qwen"])
    }
}
