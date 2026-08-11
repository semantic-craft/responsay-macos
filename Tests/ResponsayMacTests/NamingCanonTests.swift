import ResponsayCore
import XCTest
@testable import ResponsayMac

/// Canonical provider naming, product decision 2026-06-12:
/// Current-route pickers show the provider/service name people recognize; ASR
/// only adds behavior labels when the same provider exposes a materially distinct
/// lane. Model IDs live in the lower
/// "模型 ID" selector/field, not in the route title.
/// Display literals deliberately stay on their surfaces (R13: no fourth literal
/// set) — this test is the anti-drift net pinning every surface to one canon.
@MainActor
final class NamingCanonTests: XCTestCase {

    /// provider id → required display prefix. A NEW provider id failing the
    /// lookup means: add it here *and* name it per the canon.
    private let canonPrefix: [String: String] = [
        "qwen": "阿里云百炼",
        "qwen-asr-flash": "阿里云百炼",
        "volcengine-flash": "火山引擎",
        "volcengine-tts": "火山引擎",
        "doubao": "火山引擎",
        "mimo": "小米Mimo",
        "gemini": "Google Gemini",
        "deepseek": "DeepSeek",
        "minimax": "MiniMax",
        "openai": "OpenAI",
        "apple": "本机 Apple 系统原生",
        "custom": "自定义 OpenAI 兼容",
    ]

    func testProviderCatalogDisplayNamesFollowCanon() {
        for preset in ProviderCatalog.all {
            guard let prefix = canonPrefix[preset.id] else {
                XCTFail("new provider \(preset.id) — name it per the canon and add it to this table")
                continue
            }
            XCTAssertTrue(
                preset.displayName.hasPrefix(prefix),
                "\(preset.id) display \"\(preset.displayName)\" violates canon prefix \"\(prefix)\"")
        }
    }

    func testTTSPresetCatalogsFollowCanon() {
        for catalog in TTSProviderCatalogPresets.all {
            guard let prefix = canonPrefix[catalog.providerID] else {
                XCTFail("new TTS provider \(catalog.providerID) — add to canon table")
                continue
            }
            XCTAssertTrue(
                catalog.displayName.hasPrefix(prefix),
                "TTS \(catalog.providerID) display \"\(catalog.displayName)\" violates canon")
        }
    }

    func testQwenSettingsUseAudio3FlashOfficialSurface() {
        XCTAssertEqual(ProviderCatalog.qwen.defaultModels[.tts], "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(
            ProviderCatalog.qwen.endpoint(for: .tts, region: .china, plan: .payg)?.baseURL,
            "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        let voiceIDs = Set(ProviderCatalog.qwen.presetVoices.map(\.id))

        for required in ["loongeva_v3.6", "loongjohn", "longanhuan_v3.6", "longjielidou_v3.6"] {
            XCTAssertTrue(voiceIDs.contains(required), "missing Qwen settings voice \(required)")
        }
    }

    func testMiniMaxSettingsVoicesCoverMultipleLanguages() {
        let voiceIDs = Set(ProviderCatalog.minimax.presetVoices.map(\.id))

        // Curated preset (2026-06-17 trim): CN×4 / EN×4 / DE×2 / JA×2. French and Korean
        // were dropped, so multi-language coverage is now pinned to the EN/DE/JA voices that ship.
        for required in [
            "English_Trustworthy_Man", "English_Graceful_Lady",
            "German_FriendlyMan", "German_SweetLady",
            "Japanese_IntellectualSenior", "Japanese_DecisivePrincess",
        ] {
            XCTAssertTrue(voiceIDs.contains(required), "missing MiniMax settings voice \(required)")
        }
    }

    /// Technical catalog tokens (preset/voice/model names) still use half-width
    /// parens. Route picker titles are UX prose and intentionally use full-width
    /// Chinese parentheses.
    func testNoFullWidthParensOnTechnicalNamingTokens() {
        var offenders = [String]()
        for p in ProviderCatalog.all {
            if p.displayName.contains("（") { offenders.append("preset \(p.id): \(p.displayName)") }
            for v in p.presetVoices where v.displayName.contains("（") {
                offenders.append("voice \(v.id): \(v.displayName)")
            }
        }
        for c in TTSProviderCatalogPresets.all {
            if c.displayName.contains("（") { offenders.append("tts \(c.providerID)") }
            for m in c.models where m.displayName.contains("（") { offenders.append("tts model \(m.id)") }
            for v in c.voices where v.displayName.contains("（") { offenders.append("tts voice \(v.id)") }
        }
        XCTAssertTrue(offenders.isEmpty, "full-width parens in name tokens: \(offenders.joined(separator: "; "))")
    }

    func testEngineTitlesCarryCanonForms() {
        XCTAssertEqual(ASREngine.cloudQwenASRFlashRealtime.title, "阿里云百炼 · 千问实时")
        XCTAssertEqual(ASREngine.cloudMimo.title, "小米Mimo")
        XCTAssertEqual(TTSEngine.cloudMimo.title, "小米Mimo")
        XCTAssertEqual(TTSEngine.cloudQwen.title, "阿里云百炼")
        // 菜单栏 TTS 服务商名与设置页一致(menu==settings):火山引擎 = 火山引擎 · 豆包语音。
        XCTAssertEqual(TTSEngine.cloudVolcengine.title, "火山引擎 · 豆包语音")
        XCTAssertEqual(TTSEngine.sherpaKokoroLocal.title, "本机离线 Kokoro")
    }

    /// menu==settings invariant (2026-06-29): every cloud TTS engine's route/menu-bar
    /// title must EQUAL the provider name shown on the 设置·朗读 card (`ProviderCatalog`
    /// preset displayName for .tts), not just share a canon prefix. Catches the kind of
    /// drift that left 火山引擎 (menu) ≠ 火山引擎 · 豆包语音 (settings).
    func testTTSMenuTitlesMatchSettingsProviderNames() {
        for engine in TTSEngine.selectableCases where !engine.isLocal {
            guard let pid = engine.providerID,
                  let preset = ProviderCatalog.all.first(where: { $0.id == pid }) else {
                continue
            }
            XCTAssertEqual(
                engine.title, preset.displayName(for: .tts),
                "menu TTS title \"\(engine.title)\" ≠ settings name \"\(preset.displayName(for: .tts))\" for \(pid)")
        }
    }

    func testRouteTitlesDoNotExposeModelIds() {
        let routeTitles = ASREngine.allCases.map(\.title) + TTSEngine.allCases.map(\.title)
        let forbiddenFragments = [
            "mimo-v2.5", "fun-asr", "bigmodel",
            "qwen-audio", "seed-tts", "gpt-4o-mini-tts",
        ]
        for title in routeTitles {
            for fragment in forbiddenFragments {
                XCTAssertFalse(title.contains(fragment), "\(title) should leave \(fragment) to the lower model selector")
            }
        }
    }

    func testCloudModelsSortAboveLocalModels() {
        // Cloud ASR choices stay grouped first.
        XCTAssertEqual(Array(ASREngine.selectableCases.prefix(5)), [
            .cloudQwenASRFlashRealtime,
            .cloudVolcengineRealtime,
            .cloudMimo,
            .cloudOpenAI,
            .cloudGemini,
        ])
        XCTAssertNil(ASREngine(rawValue: "cloud-volcengine"))
        XCTAssertNil(ASREngine.fromStoredValue("cloud-volcengine"))
        XCTAssertEqual(Array(ASREngine.selectableCases.suffix(4)), [
            .apple,
            .sensevoiceLocal,
            .qwen3LocalASR,
            .funAsrNanoLocal,
        ])
        XCTAssertEqual(TTSEngine.selectableCases, [
            .cloudQwen,
            .cloudVolcengine,
            .cloudMimo,
            .cloudMiniMax,
            .cloudOpenAI,
            .cloudGemini,
            .sherpaKokoroLocal,
        ])
        XCTAssertFalse(ProviderCatalog.all.contains { $0.id == "qwen-team" })
        // Retired plan-specific provider ids stay absent from the provider picker.
        XCTAssertFalse(ProviderCatalog.all.contains { $0.id == "mimo-payg" })
    }

    func testCapabilityProviderOrderKeepsDomesticCloudFirstAndOpenAILow() {
        XCTAssertEqual(ProviderCatalog.presets(for: .asr).map(\.id), [
            "qwen-asr-flash", "volcengine-flash", "mimo",
            "openai", "gemini", "custom", "apple",
        ])
        XCTAssertEqual(ProviderCatalog.presets(for: .tts).map(\.id), [
            "qwen", "volcengine-tts", "mimo", "minimax", "openai", "gemini", "custom",
        ])
        XCTAssertEqual(ProviderCatalog.presets(for: .llm).map(\.id), [
            "qwen", "doubao", "mimo", "deepseek",
            "gemini", "openai", "custom",   // minimax 无此行：1.5.1 起 TTS-only
        ])
    }

    func testQwenLLMOffersPayAsYouGoEndpointsOnly() {
        XCTAssertEqual(ProviderCatalog.qwen.plans(for: .llm), [.payg])
        XCTAssertEqual(
            ProviderCatalog.qwen.endpoints(for: .llm).map(\.baseURL),
            [
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                "https://dashscope-us.aliyuncs.com/compatible-mode/v1",
                "",
                "",
            ])
        XCTAssertEqual(
            ProviderCatalog.qwen.endpoints(for: .llm)
                .compactMap(\.note),
            [
                "百炼 Responses · 华北2（北京）",
                "百炼 Responses · 新加坡",
                "百炼 Responses · 美国（弗吉尼亚）",
                "百炼 Responses · 德国（法兰克福，需 Workspace ID）",
                "百炼 Responses · 日本（东京，需 Workspace ID）",
            ])
    }

    func testLLMPresetsDefaultToLatestFastModelOnly() {
        let expectedDefaults: [String: String] = [
            "qwen": "qwen3.7-flash",
            "doubao": "doubao-seed-2-1-turbo-260628",
            "mimo": "mimo-v2.5",
            "deepseek": "deepseek-v4-flash",
            "gemini": "gemini-3.5-flash-lite",
            "openai": "chat-latest",   // 7d02e454 改为 chat-latest（曾误期望 gpt-5.5）
            // (minimax 无此行：1.5.1 起 TTS-only，LLM 档下架。)
        ]

        for (providerId, expectedModel) in expectedDefaults {
            let preset = ProviderCatalog.presets(for: .llm).first { $0.id == providerId }
            XCTAssertEqual(preset?.defaultModels[.llm], expectedModel)
            // The default model is curated and must be the first preset.
            XCTAssertEqual(preset?.presetModels[.llm]?.first, expectedModel)
            XCTAssertEqual(preset?.presetModels[.llm]?.contains(expectedModel), true)
        }
    }

    func testGeminiASRDefaultsToCheapestFlashLite() {
        let gemini = ProviderCatalog.presets(for: .asr).first { $0.id == "gemini" }
        // 听写量大 → 默认走最便宜的 flash-lite(音频输入 $0.50/1M);3.5-flash 输入 3x/输出 6x 偏贵,只作可选。
        XCTAssertEqual(gemini?.defaultModels[.asr], "gemini-3.1-flash-lite")
        XCTAssertEqual(gemini?.presetModels[.asr]?.first, "gemini-3.1-flash-lite")
        XCTAssertEqual(gemini?.presetModels[.asr]?.contains("gemini-3.5-flash"), true)
    }

    func testCapabilityLabelsUseProviderOrServiceNames() {
        XCTAssertEqual(
            ProviderCatalog.mimo.displayName(for: .asr),
            "小米Mimo")
        XCTAssertEqual(
            ProviderCatalog.mimo.displayName(for: .tts),
            "小米Mimo")
        XCTAssertEqual(
            ProviderCatalog.mimo.displayName(for: .llm),
            "小米Mimo")
        XCTAssertEqual(
            ProviderCatalog.qwenASRRealtime.displayName(for: .asr),
            "阿里云百炼 · 千问实时")
        // 智谱已退役：LLM 选择器里不再出现，preset 也已删除。
        XCTAssertFalse(ProviderCatalog.presets(for: .llm).map(\.id).contains("zhipu"))
        XCTAssertFalse(ProviderCatalog.all.map(\.id).contains("zhipu"))
        XCTAssertEqual(
            ProviderCatalog.doubao.displayName(for: .llm),
            "火山引擎 · 豆包 Seed")
    }
}
