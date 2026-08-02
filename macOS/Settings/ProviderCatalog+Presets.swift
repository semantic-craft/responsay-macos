import Foundation
import ResponsayCore

extension ProviderCatalog {
    // -- 通义千问 · 阿里云百炼 ----------
    static let qwen = ProviderPreset(
        id: "qwen", displayName: "阿里云百炼",
        capabilities: [.llm, .tts], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, "wss://dashscope.aliyuncs.com/api-ws/v1/inference", note: "Qwen-Audio-TTS · 华北2（北京）"),
            .init(.singapore, .payg, "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference", note: "Qwen-Audio-TTS · 新加坡"),
        ],
        // LLM 走 OpenAI Responses 兼容端点；上面的共享 endpoint 仅供 Qwen-Audio-TTS。
        // 官方建议迁移到业务空间专属域名；设置卡可选填 Workspace ID 并按地域派生，
        // 留空时继续使用兼容的 dashscope 通用域名。
        capabilityEndpoints: [
            .llm: [
                .init(.china, .payg, "https://dashscope.aliyuncs.com/compatible-mode/v1", note: "百炼 Responses · 华北2（北京）"),
                .init(.singapore, .payg, "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", note: "百炼 Responses · 新加坡"),
                .init(.unitedStates, .payg, "https://dashscope-us.aliyuncs.com/compatible-mode/v1", note: "百炼 Responses · 美国（弗吉尼亚）"),
                // 德国、日本文档只给出 Workspace 专属域名；留空表示必须由用户填写
                // Workspace ID 后派生，不能臆造一个通用 DashScope 域名。
                .init(.germany, .payg, "", note: "百炼 Responses · 德国（法兰克福，需 Workspace ID）"),
                .init(.japan, .payg, "", note: "百炼 Responses · 日本（东京，需 Workspace ID）"),
            ],
        ],
        defaultModels: [.llm: "qwen3.7-flash", .tts: "qwen-audio-3.0-tts-flash"],
        keyLabel: "通义千问 API Key", keyFormatHint: "sk-…",
        capabilityKeyFormatHints: [.llm: "百炼 API Key（sk-…）"],
        builtinSearch: true, isCustom: false, isLocal: false,
        presetModels: [
            // qwen3.7-max 面向技能平台工作流（听写默认仍是 flash）；不列入会被
            // LLMModelPresetFilter 从拉取结果中过滤掉，导致技能模型选不到 Max。
            .llm: ["qwen3.7-flash", "qwen3.7-max", "qwen3.6-flash", "qwen3.6-plus", "qwen3.7-plus"],
            .tts: ["qwen-audio-3.0-tts-flash"],
        ],
        presetVoices: [
            PresetVoice(id: "loongeva_v3.6", displayName: "loongeva (女·精品英文)"),
            PresetVoice(id: "loongjohn", displayName: "loongJohn (男·沉稳美音)"),
            PresetVoice(id: "longanhuan_v3.6", displayName: "龙安欢 (女·中英双语)"),
            PresetVoice(id: "longjielidou_v3.6", displayName: "龙杰力豆 (男童·中英双语)")
        ])

    // id 仍用 "qwen-asr-flash"（历史 id，避免 keychain/选择迁移）；这张卡承载的是百炼**实时语音识别**
    // 的 run-task WSS 协议（/api-ws/v1/inference）：按住说话边传边识别，松手 finish-task 出整段。
    // 旧的 OmniRealtime 引擎（/api-ws/v1/realtime + qwen3-asr-flash-realtime）已下线——它是唯一
    // 不支持任何热词的千问实时模型；存量值迁移见 QwenASRFlashRouting。
    // 端点默认走通用域名；卡片填了 Workspace ID 后派生业务空间专属域名。
    static let qwenASRRealtime = ProviderPreset(
        id: "qwen-asr-flash", displayName: "阿里云百炼 · 千问实时",
        capabilities: [.asr], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, QwenASRFlashRouting.chinaBaseURL, note: "实时语音识别 run-task · 华北2（北京）"),
            .init(.singapore, .payg, QwenASRFlashRouting.singaporeBaseURL, note: "实时语音识别 run-task · 新加坡"),
        ],
        defaultModels: [.asr: QwenASRFlashRouting.defaultModel],
        keyLabel: "通义千问 API Key", keyFormatHint: "sk-…",
        builtinSearch: false, isCustom: false, isLocal: false,
        // Fun-ASR-Realtime 与 Qwen-Audio-3.0-ASR-Flash-Streaming 共用协议与端点，但只有后者支持
        // 即时热词（vocabulary）且 language_hints 可给 4 个，所以后者作默认。
        presetModels: [.asr: [QwenASRFlashRouting.defaultModel, QwenASRFlashRouting.funASRRealtimeModel]])

    // id 仍用 "volcengine-flash"（历史 id，避免 keychain/选择迁移）；现在这张卡承载的是
    // 豆包流式（大模型流式语音识别，流式输入模式 bigmodel_nostream #580，新版 X-Api-Key 鉴权）——
    // 旧的录音文件识别标准版 2.0 整段引擎已下线，迁移到流式。
    static let volcengineFlash = ProviderPreset(
        id: "volcengine-flash", displayName: "火山引擎 · 豆包流式",
        capabilities: [.asr], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream", note: "豆包流式2.0（seedasr）· 流式输入·整段语义 · volc.seedasr.sauc.duration"),
        ],
        defaultModels: [.asr: "bigmodel"],
        keyLabel: "火山引擎 API Key", keyFormatHint: "新版语音控制台 API Key（需开通豆包大模型流式语音识别2.0）",
        capabilityKeyFormatHints: [.asr: "新版语音控制台 API Key（需开通大模型流式语音识别）"],
        builtinSearch: false, isCustom: false, isLocal: false,
        presetModels: [.asr: ["bigmodel"]])

    static let volcengineTTS = ProviderPreset(
        id: "volcengine-tts", displayName: "火山引擎 · 豆包语音",
        capabilities: [.tts], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, "https://openspeech.bytedance.com/api/v3", note: "豆包语音合成大模型 2.0 HTTP"),
        ],
        defaultModels: [.tts: "seed-tts-2.0"],
        keyLabel: "火山引擎 API Key", keyFormatHint: "新版控制台 API Key",
        builtinSearch: false, isCustom: false, isLocal: false,
        presetModels: [.tts: ["seed-tts-2.0"]],
        presetVoices: [
            PresetVoice(id: "zh_female_xiaohe_uranus_bigtts", displayName: "小何 2.0 (女·中文)"),
            PresetVoice(id: "zh_male_m191_uranus_bigtts", displayName: "云舟 2.0 (男·中文)"),
            PresetVoice(id: "zh_female_vv_uranus_bigtts", displayName: "Vivi 2.0 (女·多语种+方言)"),
            PresetVoice(id: "en_male_tim_uranus_bigtts", displayName: "Tim (男·美式英语)"),
            PresetVoice(id: "en_female_dacey_uranus_bigtts", displayName: "Dacey (女·美式英语)"),
            PresetVoice(id: "en_female_authoritative-informative_uranus_bigtts", displayName: "Margaret (女·美式英语·沉稳)"),
            PresetVoice(id: "en_female_joanne_uranus_bigtts", displayName: "Joanne (女·美式英语·有声阅读)"),
            PresetVoice(id: "de_female_bv081_uranus_bigtts", displayName: "Stella (女·德语)"),
            PresetVoice(id: "de_male_sven_uranus_bigtts", displayName: "Sven (男·德语)"),
            PresetVoice(id: "ja_female_bv522_uranus_bigtts", displayName: "Hana (女·日语)")
        ])

    static let doubao = ProviderPreset(
        id: "doubao", displayName: "火山引擎 · 豆包 Seed",
        capabilities: [.llm], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, "https://ark.cn-beijing.volces.com/api/v3", note: "火山方舟 OpenAI 兼容 · 北京"),
        ],
        defaultModels: [.llm: "doubao-seed-2-1-turbo-260628"],
        keyLabel: "火山方舟 API Key", keyFormatHint: "火山方舟 API Key",
        capabilityKeyFormatHints: [.llm: "Doubao Seed 2.1 · 火山方舟 API Key"],
        builtinSearch: true, isCustom: false, isLocal: false,
        presetModels: [
            // turbo = 2.1 快档(默认)、pro = 2.1 重档;两者 256k 上下文 + 深度思考 + 工具调用。
            .llm: [
                "doubao-seed-2-1-turbo-260628",
                "doubao-seed-2-1-pro-260628",
            ],
        ])

    // -- MiMo（小米）— 国内拆按量付费 / Token Plan，海外仅 Token Plan；接入点随档切换。
    // 一个供应商一套 key 槽：按量付费填 sk-、Token Plan 填 tp-（auth 都走 api-key 头，
    // host 随下拉框变）。TTS 早已是这套形态。 ----------------------------------------
    static let mimo = ProviderPreset(
        id: "mimo", displayName: "小米Mimo",
        capabilities: [.asr, .llm, .tts], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .package, "https://token-plan-cn.xiaomimimo.com/v1", note: "Token Plan · 中国"),
            .init(.china, .payg, "https://api.xiaomimimo.com/v1", note: "开放平台按量 API · 中国"),
            .init(.singapore, .package, "https://token-plan-sgp.xiaomimimo.com/v1", note: "Token Plan · 新加坡"),
            .init(.europe, .package, "https://token-plan-ams.xiaomimimo.com/v1", note: "Token Plan · 欧洲"),
        ],
        capabilityEndpoints: [
            .asr: [
                .init(.china, .package, "https://token-plan-cn.xiaomimimo.com/v1", note: "Token Plan · 中国 · ASR 已验证"),
                .init(.china, .payg, "https://api.xiaomimimo.com/v1", note: "开放平台按量 API · 中国"),
                .init(.singapore, .package, "https://token-plan-sgp.xiaomimimo.com/v1", note: "Token Plan · 新加坡"),
                .init(.europe, .package, "https://token-plan-ams.xiaomimimo.com/v1", note: "Token Plan · 欧洲"),
            ],
            .llm: [
                .init(.china, .package, "https://token-plan-cn.xiaomimimo.com/v1", note: "Token Plan · 中国"),
                .init(.china, .payg, "https://api.xiaomimimo.com/v1", note: "开放平台按量 API · 中国"),
                .init(.singapore, .package, "https://token-plan-sgp.xiaomimimo.com/v1", note: "Token Plan · 新加坡"),
                .init(.europe, .package, "https://token-plan-ams.xiaomimimo.com/v1", note: "Token Plan · 欧洲"),
            ],
            .tts: [
                .init(.china, .payg, "https://api.xiaomimimo.com/v1", note: "开放平台按量 API · TTS 限时免费"),
                .init(.china, .package, "https://token-plan-cn.xiaomimimo.com/v1", note: "Token Plan · 中国"),
            ],
        ],
        defaultModels: [.asr: "mimo-v2.5-asr", .llm: "mimo-v2.5", .tts: "mimo-v2.5-tts"],
        keyLabel: "MiMo API Key", keyFormatHint: "tp-…",
        capabilityKeyFormatHints: [
            .asr: "按量付费填 sk-…；Token Plan 填 tp-…",
            .llm: "按量付费填 sk-…；Token Plan 填 tp-…",
            .tts: "按量付费填普通 Key；Token Plan 填 tp-…",
        ],
        builtinSearch: true, isCustom: false, isLocal: false,
        presetModels: [
            .asr: ["mimo-v2.5-asr"],
            .llm: ["mimo-v2.5"],
            .tts: ["mimo-v2.5-tts"]
        ],
        presetVoices: [
            PresetVoice(id: "Chloe", displayName: "Chloe (女·英语)"),
            PresetVoice(id: "Mia", displayName: "Mia (女·英语)"),
            PresetVoice(id: "Dean", displayName: "Dean (男·英语)"),
            PresetVoice(id: "冰糖", displayName: "冰糖 (女·中文)"),
            PresetVoice(id: "苏打", displayName: "苏打 (男·中文)")
        ])

    static let minimax = ProviderPreset(
        id: "minimax", displayName: "MiniMax",
        // TTS-only since 1.5.1 (user decision 2026-07-20): the LLM lane opened in 423 is retired —
        // 文本模型下架，语音合成保留。A stored `byok.llm.provider = "minimax"` now falls back to the
        // catalog default via ProviderConfigDispatcher; the shared key stays (TTS uses it).
        capabilities: [.tts], credentialShape: .apiKey,
        endpoints: [
            .init(.china, .payg, "https://api.minimaxi.com/v1"),
            .init(.intl, .payg, "https://api.minimax.io/v1"),
        ],
        defaultModels: [.tts: "speech-2.8-hd"],
        keyLabel: "MiniMax API Key", keyFormatHint: nil,
        builtinSearch: false, isCustom: false, isLocal: false,
        presetModels: [
            .tts: [
                "speech-2.8-hd", "speech-2.8-turbo",
                "speech-2.6-hd", "speech-2.6-turbo",
                "speech-02-hd", "speech-02-turbo",
                "speech-01-hd", "speech-01-turbo",
            ],
        ],
        presetVoices: [
            PresetVoice(id: "male-qn-qingse", displayName: "青涩青年 (中文)"),
            PresetVoice(id: "male-qn-jingying", displayName: "精英青年 (中文)"),
            PresetVoice(id: "female-shaonv", displayName: "少女 (中文)"),
            PresetVoice(id: "female-yujie", displayName: "御姐 (中文)"),
            PresetVoice(id: "English_Trustworthy_Man", displayName: "Trustworthy Man (英文)"),
            PresetVoice(id: "Sweet_Girl", displayName: "Sweet Girl (英文)"),
            PresetVoice(id: "Attractive_Girl", displayName: "Attractive Girl (英文)"),
            PresetVoice(id: "English_Graceful_Lady", displayName: "Graceful Lady (英文)"),
            PresetVoice(id: "German_FriendlyMan", displayName: "Friendly Man (德文)"),
            PresetVoice(id: "German_SweetLady", displayName: "Sweet Lady (德文)"),
            PresetVoice(id: "Japanese_IntellectualSenior", displayName: "Intellectual Senior (日文)"),
            PresetVoice(id: "Japanese_DecisivePrincess", displayName: "Decisive Princess (日文)")
        ])

    // Kimi (Moonshot) was removed as a provider: its K2.x models are reasoning models
    // that reject any temperature/top_p except mode-locked fixed values (temp 1 / 0.6,
    // top_p 0.95) — a hard 400 against the app's uniform OpenAI-compatible generation
    // profile. Too brittle to carry for an IME; a custom OpenAI-compatible endpoint can
    // still be pointed at Moonshot by power users who want it.

    static let deepseek = ProviderPreset(
        id: "deepseek", displayName: "DeepSeek",
        capabilities: [.llm], credentialShape: .apiKey,
        endpoints: [.init(.global, .payg, "https://api.deepseek.com/v1")],
        defaultModels: [.llm: "deepseek-v4-flash"],
        keyLabel: "DeepSeek API Key", keyFormatHint: "sk-…",
        // 联网靠 Responses 的服务端 web_search 工具，只有 deepseek-v4-flash 走那条路由。
        builtinSearch: true, isCustom: false, isLocal: false,
        presetModels: [.llm: ["deepseek-v4-flash"]])

    static let openAI = ProviderPreset(
        id: "openai", displayName: "OpenAI",
        capabilities: [.asr, .llm, .tts], credentialShape: .apiKey,
        endpoints: [.init(.global, .payg, "https://api.openai.com/v1")],
        defaultModels: [.asr: "gpt-4o-transcribe", .llm: "chat-latest", .tts: "gpt-4o-mini-tts"],
        keyLabel: "OpenAI API Key", keyFormatHint: "sk-…",
        builtinSearch: false, isCustom: false, isLocal: false,
        presetModels: [.asr: ["gpt-4o-transcribe", "whisper-1"],
                       .llm: ["chat-latest"],
                       .tts: ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]],
        presetVoices: [
            PresetVoice(id: "alloy", displayName: "Alloy (中性)"),
            PresetVoice(id: "nova", displayName: "Nova (女·明快)"),
            PresetVoice(id: "coral", displayName: "Coral (女·温暖)"),
            PresetVoice(id: "onyx", displayName: "Onyx (男·低沉)"),
            PresetVoice(id: "sage", displayName: "Sage (沉稳)")
        ])

    static let gemini = ProviderPreset(
        id: "gemini", displayName: "Google Gemini",
        capabilities: [.asr, .llm, .tts], credentialShape: .apiKey,
        endpoints: [.init(.global, .payg, "https://generativelanguage.googleapis.com/v1beta/openai/")],
        // ASR + TTS use the NATIVE host (not /v1beta/openai/): both go through
        // :generateContent (audio inline / responseModalities:["AUDIO"]), not the
        // OpenAI-compat surface. ASR auth is in DirectGeminiTranscriptionAPI; TTS in
        // GeminiTTSAdapter. The native-host override keeps the settings card from
        // prefilling /v1beta/openai/ into byok.tts.baseURL (which would 404).
        capabilityEndpoints: [
            .asr: [.init(.global, .payg, "https://generativelanguage.googleapis.com/v1beta/")],
            .tts: [.init(.global, .payg, "https://generativelanguage.googleapis.com/v1beta/")],
        ],
        defaultModels: [.asr: "gemini-3.1-flash-lite", .llm: "gemini-3.5-flash-lite",
                        .tts: "gemini-3.1-flash-tts-preview"],
        keyLabel: "Gemini API Key", keyFormatHint: "AIza…",
        builtinSearch: false, isCustom: false, isLocal: false,
        // LLM (text) models only on the .llm lane — Gemini TTS is a SEPARATE catalog
        // (TTSProviderCatalogPresets.gemini); kept apart so a /models fetch never leaks
        // *-tts / *-image / *-embedding ids into the LLM picker (whitelist — see
        // LLMModelPresetFilter). The .asr lane lists the multimodal models that can
        // transcribe (flash tier — Pro is overkill/slow for dictation). (2026-06-16)
        presetModels: [
            // ASR 默认走最便宜的 flash-lite（音频输入 $0.50/1M ≈ $0.001/min,输出 $1.50/1M）——
            // 听写量大时 3.5-flash 成本较高，因此只作可选项。
            .asr: [
                "gemini-3.1-flash-lite",   // 默认 — 最便宜最快,适合 IME 听写
                "gemini-3.5-flash-lite",   // 2026-07-21 新代 lite(音频输入 $0.30/1M,更便宜;质量待实测)
                "gemini-2.5-flash-lite",   // 更便宜的旧代(音频输入 $0.30/1M)
                "gemini-2.5-flash",        // 旧代 flash
                "gemini-3-flash-preview",  // Gemini 3 flash(preview)
                "gemini-3.5-flash",        // 质量最好但最贵(可选)
            ],
            .llm: [
                "gemini-3.5-flash-lite",   // default — 2026-07-21 stable, cheapest/fastest 3.5 (1M ctx, thinking)
                "gemini-3.1-flash-lite",   // prior default — fast / low-cost, fits the IME
                "gemini-3.5-flash",        // newest stable flash (1M ctx, thinking)
                "gemini-3-flash-preview",  // Gemini 3 flash (preview)
                "gemini-3.1-pro-preview",  // Gemini 3 Pro (text)
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-flash-latest",     // latest-flash alias (auto-tracks newest)
            ],
            // Single TTS model — newest + fastest (see TTSProviderCatalogPresets.gemini).
            .tts: ["gemini-3.1-flash-tts-preview"],
        ],
        presetVoices: [
            PresetVoice(id: "Kore", displayName: "Kore (清晰)"),
            PresetVoice(id: "Puck", displayName: "Puck (明亮)"),
            PresetVoice(id: "Charon", displayName: "Charon (沉稳)"),
            PresetVoice(id: "Sadaltager", displayName: "Sadaltager (学者)")
        ])

    static let custom = ProviderPreset(
        id: "custom", displayName: "自定义 OpenAI 兼容",
        capabilities: [.asr, .llm, .tts], credentialShape: .apiKey,
        endpoints: [.init(.global, .payg, "", note: "https://your-endpoint/v1")],
        defaultModels: [:],
        keyLabel: "API Key", keyFormatHint: nil,
        builtinSearch: false, isCustom: true, isLocal: false)

    static let appleLocal = ProviderPreset(
        id: "apple", displayName: "本机 Apple 系统原生",
        capabilities: [.asr], credentialShape: .apiKey,
        endpoints: [], defaultModels: [:],
        keyLabel: "", keyFormatHint: nil,
        builtinSearch: false, isCustom: false, isLocal: true)
}
