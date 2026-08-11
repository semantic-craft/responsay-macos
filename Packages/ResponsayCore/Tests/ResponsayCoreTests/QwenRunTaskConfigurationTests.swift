import Testing
@testable import ResponsayCore

@Suite("QwenASRHotwords")
struct QwenASRHotwordsTests {
    @Test func enforcesDocumentedTextRules() {
        #expect(QwenASRHotwords.isValid("厄洛替尼盐酸盐"))
        #expect(QwenASRHotwords.isValid("EGFR抑制剂"))
        #expect(QwenASRHotwords.isValid("Human immunodeficiency virus type 1"))
        #expect(!QwenASRHotwords.isValid("这是一个远远超过十五个字符上限的超长词条应当被丢弃"))
        #expect(!QwenASRHotwords.isValid(
            "The effect of temperature variations on enzyme activity in reactions"))
        #expect(!QwenASRHotwords.isValid(""))
    }

    @Test func vocabularyDropsInvalidTermsAndBlanks() {
        let vocabulary = QwenASRHotwords.vocabulary(
            from: ["Westlaw", "  ", "这是一个远远超过十五个字符上限的超长词条应当被丢弃", " SSRN "],
            model: "qwen-audio-3.0-asr-flash-streaming")
        #expect(vocabulary == ["Westlaw": 4, "SSRN": 4])
    }

    @Test func onlyQwenAudio30AcceptsInstantVocabulary() {
        #expect(QwenASRHotwords.supportsInstantVocabulary(
            model: "qwen-audio-3.0-asr-flash-streaming"))
        #expect(QwenASRHotwords.supportsInstantVocabulary(model: "qwen-audio-3.0-asr-flash"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "fun-asr-realtime"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "qwen3-asr-flash-realtime"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "paraformer-realtime-v2"))
    }

    @Test func precompiledVocabularyIdentifierAcceptsAnOpaqueSuffix() {
        #expect(QwenASRHotwords.normalizedVocabularyIdentifier(" vocab-deadbeef ")
                == "vocab-deadbeef")
        #expect(QwenASRHotwords.normalizedVocabularyIdentifier("vocab-prefix-deadbeef")
                == "vocab-prefix-deadbeef")
        #expect(QwenASRHotwords.normalizedVocabularyIdentifier("vocab-") == nil)
        #expect(QwenASRHotwords.normalizedVocabularyIdentifier("vocab-private words") == nil)
    }

    @Test func onlyDocumentedLanguageCodesBecomeHints() {
        #expect(QwenASRHotwords.languageHint("zh") == "zh")
        #expect(QwenASRHotwords.languageHint(" EN ") == "en")
        #expect(QwenASRHotwords.languageHint("zh-CN") == nil)
        #expect(QwenASRHotwords.languageHint("") == nil)
    }

    @Test func mixedLocaleUsesTwoHintsForQwenAndOneForFunASR() {
        #expect(QwenASRHotwords.languageHints(
            for: .mixed,
            model: "qwen-audio-3.0-asr-flash-streaming") == ["zh", "en"])
        #expect(QwenASRHotwords.languageHints(
            for: .mixed,
            model: "fun-asr-realtime") == ["zh"])
        #expect(QwenASRHotwords.languageHints(
            for: .automatic,
            model: "qwen-audio-3.0-asr-flash-streaming").isEmpty)
    }
}

@Suite("QwenRunTaskEndpoint")
struct QwenRunTaskEndpointTests {
    @Test func genericHostWhenNoWorkspaceIsConfigured() {
        #expect(QwenRunTaskEndpoint(region: .china).url.absoluteString
                == "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        #expect(QwenRunTaskEndpoint(region: .singapore).url.absoluteString
                == "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference")
        #expect(!QwenRunTaskEndpoint(region: .china).usesDedicatedHost)
    }

    @Test func workspaceIDDerivesTheDedicatedHostPerRegion() {
        #expect(QwenRunTaskEndpoint(region: .china, workspaceID: " ws-ABC123 ").url.absoluteString
                == "wss://ws-abc123.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
        #expect(QwenRunTaskEndpoint(region: .singapore, workspaceID: "ws-abc123").url.absoluteString
                == "wss://ws-abc123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
        #expect(QwenRunTaskEndpoint(region: .china, workspaceID: "ws-abc123").usesDedicatedHost)
        #expect(QwenRunTaskEndpoint(region: .china, workspaceID: "ws-abc123").supportsHotwords)
        #expect(QwenRunTaskEndpoint(region: .singapore).supportsHotwords)
        #expect(!QwenRunTaskEndpoint(
            region: .singapore,
            workspaceID: "ws-abc123").supportsHotwords)
    }

    @Test func malformedWorkspaceIDCannotInjectAHost() {
        for bad in ["ws-abc123.evil.example", "https://evil.example", "evil.example",
                    "ws-", "ws-abc_123", "ws-abc/123", ""] {
            let endpoint = QwenRunTaskEndpoint(region: .china, workspaceID: bad)
            #expect(!endpoint.usesDedicatedHost, "\(bad) must not become a host")
            #expect(endpoint.url.absoluteString
                    == "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        }
    }

    @Test func precompiledVocabularyBindingRequiresExactEnvironmentAndFingerprint() {
        let binding = QwenPrecompiledVocabularyBinding(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            region: .china,
            workspaceID: "ws-abc123",
            vocabularyFingerprint: "fingerprint-1")
        let endpoint = QwenRunTaskEndpoint(region: .china, workspaceID: " ws-ABC123 ")

        #expect(binding.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: endpoint,
            vocabularyFingerprint: "fingerprint-1") == "vocab-curated-a1b2c3")
        #expect(binding.resolvedIdentifier(
            model: "fun-asr-realtime",
            endpoint: endpoint,
            vocabularyFingerprint: "fingerprint-1") == nil)
        #expect(binding.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .singapore, workspaceID: "ws-abc123"),
            vocabularyFingerprint: "fingerprint-1") == nil)
        #expect(binding.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china, workspaceID: "ws-other"),
            vocabularyFingerprint: "fingerprint-1") == nil)
        #expect(binding.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: endpoint,
            vocabularyFingerprint: "stale-fingerprint") == nil)
    }

    @Test func precompiledVocabularyBindingRejectsMalformedValues() {
        let malformedID = QwenPrecompiledVocabularyBinding(
            identifier: "vocab contains private words",
            model: QwenRunTaskEndpoint.defaultModel,
            region: .china,
            workspaceID: nil,
            vocabularyFingerprint: "fingerprint-1")
        let malformedWorkspace = QwenPrecompiledVocabularyBinding(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            region: .china,
            workspaceID: "ws-abc.evil.example",
            vocabularyFingerprint: "fingerprint-1")

        #expect(malformedID.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyFingerprint: "fingerprint-1") == nil)
        #expect(malformedWorkspace.resolvedIdentifier(
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyFingerprint: "fingerprint-1") == nil)
    }
}
