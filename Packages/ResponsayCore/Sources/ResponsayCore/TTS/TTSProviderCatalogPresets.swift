import Foundation

/// Cloud TTS providers as **data** (issue 196), mirroring the `ai-voice-studio`
/// extension's `ProviderCatalog{models,voices,defaults}`. Voices/models drive the
/// 朗读引擎 + 音色 pickers; endpoints + auth live on the macOS side (BYOK direct,
/// keys in Keychain). IME subset — a handful of voices per provider, not the full
/// studio lists; no voice clone/design/multi-speaker.
///
/// `supportsWordTiming` is `false` for every provider (none of the surveyed cloud
/// TTS APIs return word timing) → highlight reuses the proportional aligner (135).
public enum TTSProviderCatalogPresets {
    public static let all: [TTSProviderCatalog] = [qwen, volcengine, mimo, minimax, gemini, openai]

    public static func catalog(for providerID: TTSProviderID) -> TTSProviderCatalog? {
        all.first { $0.providerID == providerID }
    }

    // MARK: - 阿里云百炼 (DashScope / Qwen) — strong Chinese + dialects

    public static let qwen = TTSProviderCatalog(
        providerID: "qwen",
        displayName: "阿里云百炼",
        models: [
            TTSModelSpec(
                id: "qwen-audio-3.0-tts-flash",
                displayName: "qwen-audio-3.0-tts-flash",
                supportsStreaming: true,
                supportsRealtimeWS: true,
                maxCharsPerRequest: 20_000),
        ],
        voices: [
            TTSVoiceSpec(
                id: "loongeva_v3.6",
                displayName: "loongeva (女·精品英文)",
                languageHints: ["en"],
                genderHint: "female"),
            TTSVoiceSpec(
                id: "loongjohn",
                displayName: "loongJohn (男·沉稳美音)",
                languageHints: ["en"],
                genderHint: "male"),
            TTSVoiceSpec(
                id: "longanhuan_v3.6",
                displayName: "龙安欢 (女·中英双语)",
                languageHints: ["zh", "en"],
                genderHint: "female"),
            TTSVoiceSpec(
                id: "longjielidou_v3.6",
                displayName: "龙杰力豆 (男童·中英双语)",
                languageHints: ["zh", "en"],
                genderHint: "male"),
        ],
        defaults: TTSDefaults(modelID: "qwen-audio-3.0-tts-flash",
                              voiceID: "loongeva_v3.6",
                              sampleRate: TTSAudio.defaultSampleRate))

    // MARK: - 火山引擎 (Volcengine) — curated seed-tts-2.0 voices

    public static let volcengine = TTSProviderCatalog(
        providerID: "volcengine-tts",
        displayName: "火山引擎 · 豆包语音",
        models: [
            TTSModelSpec(id: "seed-tts-2.0", displayName: "seed-tts-2.0", supportsStreaming: true),
        ],
        // 10 款精选，女:男 = 7:3；中文 3（含多语种 Vivi）、英文 4、德 2、日 1。
        // 中文打头 → 默认音色对中文为主的用户友好。
        voices: [
            // 中文 ×2（1 女 1 男）
            TTSVoiceSpec(id: "zh_female_xiaohe_uranus_bigtts", displayName: "小何 2.0 (女·中文)",
                         languageHints: ["zh"], genderHint: "female"),
            TTSVoiceSpec(id: "zh_male_m191_uranus_bigtts", displayName: "云舟 2.0 (男·中文)",
                         languageHints: ["zh"], genderHint: "male"),
            TTSVoiceSpec(id: "zh_female_vv_uranus_bigtts", displayName: "Vivi 2.0 (女·多语种+方言)",
                         languageHints: ["zh", "ja", "es"], genderHint: "female", styleTags: ["dialect"]),
            // 英文 ×4（1 男 3 女）
            TTSVoiceSpec(id: "en_male_tim_uranus_bigtts", displayName: "Tim (男·美式英语)",
                         languageHints: ["en-US"], genderHint: "male"),
            TTSVoiceSpec(id: "en_female_dacey_uranus_bigtts", displayName: "Dacey (女·美式英语)",
                         languageHints: ["en-US"], genderHint: "female"),
            TTSVoiceSpec(id: "en_female_authoritative-informative_uranus_bigtts", displayName: "Margaret (女·美式英语·沉稳)",
                         languageHints: ["en-US"], genderHint: "female"),
            TTSVoiceSpec(id: "en_female_joanne_uranus_bigtts", displayName: "Joanne (女·美式英语·有声阅读)",
                         languageHints: ["en-US"], genderHint: "female"),
            // 德语 ×2（seed-tts-2.0 全 catalog 仅此两款）
            TTSVoiceSpec(id: "de_female_bv081_uranus_bigtts", displayName: "Stella (女·德语)",
                         languageHints: ["de"], genderHint: "female"),
            TTSVoiceSpec(id: "de_male_sven_uranus_bigtts", displayName: "Sven (男·德语)",
                         languageHints: ["de"], genderHint: "male"),
            // 日语 ×1
            TTSVoiceSpec(id: "ja_female_bv522_uranus_bigtts", displayName: "Hana (女·日语)",
                         languageHints: ["ja"], genderHint: "female"),
        ],
        defaults: TTSDefaults(modelID: "seed-tts-2.0",
                              voiceID: "zh_female_xiaohe_uranus_bigtts",
                              sampleRate: TTSAudio.defaultSampleRate))

    // MARK: - Gemini — multilingual, natural-language style

    public static let gemini = TTSProviderCatalog(
        providerID: "gemini",
        displayName: "Google Gemini",
        models: [
            // Single model — newest + fastest. Verified against Google's live speech-generation
            // docs (2026-06-29) and AI Voice Studio v0.12.7: gemini-3.1-flash-tts-preview is the
            // model in every current Google sample. No 2.5 pro/flash. ponytail: preview-tier id —
            // a wrong/retired id surfaces as a visible BYOK API error, swap when Google rotates it.
            TTSModelSpec(id: "gemini-3.1-flash-tts-preview", displayName: "gemini-3.1-flash-tts-preview"),
        ],
        voices: [
            TTSVoiceSpec(id: "Kore", displayName: "Kore (清晰)", languageHints: ["en", "zh"]),
            TTSVoiceSpec(id: "Puck", displayName: "Puck (明亮)", languageHints: ["en", "zh"]),
            TTSVoiceSpec(id: "Charon", displayName: "Charon (沉稳)", languageHints: ["en", "zh"]),
            TTSVoiceSpec(id: "Sadaltager", displayName: "Sadaltager (学者)", languageHints: ["en", "zh"]),
        ],
        defaults: TTSDefaults(modelID: "gemini-3.1-flash-tts-preview", voiceID: "Kore", sampleRate: TTSAudio.defaultSampleRate))

    // MARK: - OpenAI — cleanest API, steerable

    public static let openai = TTSProviderCatalog(
        providerID: "openai",
        displayName: "OpenAI",
        models: [
            TTSModelSpec(id: "gpt-4o-mini-tts", displayName: "gpt-4o-mini-tts"),
        ],
        voices: [
            TTSVoiceSpec(id: "alloy", displayName: "Alloy (中性)", languageHints: ["en", "zh"]),
            TTSVoiceSpec(id: "nova", displayName: "Nova (女·明快)", languageHints: ["en", "zh"], genderHint: "female"),
            TTSVoiceSpec(id: "coral", displayName: "Coral (女·温暖)", languageHints: ["en", "zh"], genderHint: "female"),
            TTSVoiceSpec(id: "onyx", displayName: "Onyx (男·低沉)", languageHints: ["en", "zh"], genderHint: "male"),
            TTSVoiceSpec(id: "sage", displayName: "Sage (沉稳)", languageHints: ["en", "zh"]),
        ],
        defaults: TTSDefaults(modelID: "gpt-4o-mini-tts", voiceID: "alloy", sampleRate: TTSAudio.defaultSampleRate))

    // MARK: - 小米Mimo (Xiaomi) — bilingual, OpenAI-compatible

    public static let mimo = TTSProviderCatalog(
        providerID: "mimo",
        displayName: "小米Mimo",
        models: [
            TTSModelSpec(id: "mimo-v2.5-tts", displayName: "mimo-v2.5-tts"),
        ],
        voices: [
            TTSVoiceSpec(id: "Chloe", displayName: "Chloe (女·英语)", languageHints: ["en"], genderHint: "female"),
            TTSVoiceSpec(id: "Mia", displayName: "Mia (女·英语)", languageHints: ["en"], genderHint: "female"),
            TTSVoiceSpec(id: "Dean", displayName: "Dean (男·英语)", languageHints: ["en"], genderHint: "male"),
            TTSVoiceSpec(id: "冰糖", displayName: "冰糖 (女·中文)", languageHints: ["zh"], genderHint: "female"),
            TTSVoiceSpec(id: "苏打", displayName: "苏打 (男·中文)", languageHints: ["zh"], genderHint: "male"),
        ],
        defaults: TTSDefaults(modelID: "mimo-v2.5-tts", voiceID: "Chloe", sampleRate: TTSAudio.defaultSampleRate))

    // MARK: - MiniMax — expressive bilingual voices, HTTP `/t2a_v2`

    public static let minimax = TTSProviderCatalog(
        providerID: "minimax",
        displayName: "MiniMax",
        models: [
            TTSModelSpec(id: "speech-2.8-hd", displayName: "speech-2.8-hd",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
            TTSModelSpec(id: "speech-2.8-turbo", displayName: "speech-2.8-turbo",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
            TTSModelSpec(id: "speech-2.6-hd", displayName: "speech-2.6-hd",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
            TTSModelSpec(id: "speech-2.6-turbo", displayName: "speech-2.6-turbo",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
            TTSModelSpec(id: "speech-02-hd", displayName: "speech-02-hd",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
            TTSModelSpec(id: "speech-02-turbo", displayName: "speech-02-turbo",
                         supportsStreaming: true, maxCharsPerRequest: 10_000),
        ],
        voices: [
            TTSVoiceSpec(id: "male-qn-qingse", displayName: "青涩青年 (中文)",
                         languageHints: ["zh"], genderHint: "male"),
            TTSVoiceSpec(id: "male-qn-jingying", displayName: "精英青年 (中文)",
                         languageHints: ["zh"], genderHint: "male"),
            TTSVoiceSpec(id: "female-shaonv", displayName: "少女 (中文)",
                         languageHints: ["zh"], genderHint: "female"),
            TTSVoiceSpec(id: "female-yujie", displayName: "御姐 (中文)",
                         languageHints: ["zh"], genderHint: "female"),
            TTSVoiceSpec(id: "Cantonese_ProfessionalHost（F)", displayName: "Professional Host F (粤语)",
                         languageHints: ["zh-HK"], genderHint: "female"),
            TTSVoiceSpec(id: "Cantonese_PlayfulMan", displayName: "Playful Man (粤语)",
                         languageHints: ["zh-HK"], genderHint: "male"),
            TTSVoiceSpec(id: "English_Trustworthy_Man", displayName: "Trustworthy Man (英文)",
                         languageHints: ["en"], genderHint: "male"),
            TTSVoiceSpec(id: "English_Graceful_Lady", displayName: "Graceful Lady (英文)",
                         languageHints: ["en"], genderHint: "female"),
            TTSVoiceSpec(id: "Sweet_Girl", displayName: "Sweet Girl (英文)",
                         languageHints: ["en"], genderHint: "female"),
            TTSVoiceSpec(id: "Attractive_Girl", displayName: "Attractive Girl (英文)",
                         languageHints: ["en"], genderHint: "female"),
            TTSVoiceSpec(id: "Japanese_IntellectualSenior", displayName: "Intellectual Senior (日文)",
                         languageHints: ["ja"], genderHint: "male"),
            TTSVoiceSpec(id: "Japanese_DecisivePrincess", displayName: "Decisive Princess (日文)",
                         languageHints: ["ja"], genderHint: "female"),
            TTSVoiceSpec(id: "Korean_SweetGirl", displayName: "Sweet Girl (韩文)",
                         languageHints: ["ko"], genderHint: "female"),
            TTSVoiceSpec(id: "Korean_CheerfulBoyfriend", displayName: "Cheerful Boyfriend (韩文)",
                         languageHints: ["ko"], genderHint: "male"),
            TTSVoiceSpec(id: "Spanish_SereneWoman", displayName: "Serene Woman (西班牙文)",
                         languageHints: ["es"], genderHint: "female"),
            TTSVoiceSpec(id: "Spanish_RationalMan", displayName: "Rational Man (西班牙文)",
                         languageHints: ["es"], genderHint: "male"),
            TTSVoiceSpec(id: "Portuguese_SentimentalLady", displayName: "Sentimental Lady (葡萄牙文)",
                         languageHints: ["pt"], genderHint: "female"),
            TTSVoiceSpec(id: "Portuguese_BossyLeader", displayName: "Bossy Leader (葡萄牙文)",
                         languageHints: ["pt"], genderHint: "male"),
            TTSVoiceSpec(id: "French_Male_Speech_New", displayName: "Level-Headed Man (法文)",
                         languageHints: ["fr"], genderHint: "male"),
            TTSVoiceSpec(id: "French_MovieLeadFemale", displayName: "Movie Lead Female (法文)",
                         languageHints: ["fr"], genderHint: "female"),
            TTSVoiceSpec(id: "German_FriendlyMan", displayName: "Friendly Man (德文)",
                         languageHints: ["de"], genderHint: "male"),
            TTSVoiceSpec(id: "German_SweetLady", displayName: "Sweet Lady (德文)",
                         languageHints: ["de"], genderHint: "female"),
            TTSVoiceSpec(id: "Russian_ReliableMan", displayName: "Reliable Man (俄文)",
                         languageHints: ["ru"], genderHint: "male"),
            TTSVoiceSpec(id: "Russian_AmbitiousWoman", displayName: "Ambitious Woman (俄文)",
                         languageHints: ["ru"], genderHint: "female"),
            TTSVoiceSpec(id: "Italian_BraveHeroine", displayName: "Brave Heroine (意大利文)",
                         languageHints: ["it"], genderHint: "female"),
            TTSVoiceSpec(id: "Italian_Narrator", displayName: "Narrator (意大利文)",
                         languageHints: ["it"], genderHint: "male"),
            TTSVoiceSpec(id: "Arabic_CalmWoman", displayName: "Calm Woman (阿拉伯文)",
                         languageHints: ["ar"], genderHint: "female"),
            TTSVoiceSpec(id: "Arabic_FriendlyGuy", displayName: "Friendly Guy (阿拉伯文)",
                         languageHints: ["ar"], genderHint: "male"),
            TTSVoiceSpec(id: "Thai_male_1_sample8", displayName: "Serene Man (泰文)",
                         languageHints: ["th"], genderHint: "male"),
            TTSVoiceSpec(id: "Thai_female_1_sample1", displayName: "Confident Woman (泰文)",
                         languageHints: ["th"], genderHint: "female"),
            TTSVoiceSpec(id: "hindi_male_1_v2", displayName: "Trustworthy Advisor (印地文)",
                         languageHints: ["hi"], genderHint: "male"),
            TTSVoiceSpec(id: "hindi_female_2_v1", displayName: "Tranquil Woman (印地文)",
                         languageHints: ["hi"], genderHint: "female"),
        ],
        defaults: TTSDefaults(modelID: "speech-2.8-hd", voiceID: "male-qn-qingse", sampleRate: 32_000))
}
