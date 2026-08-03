import Foundation
import Testing
@testable import ResponsayCore

/// Pins the 百炼 实时语音识别 run-task wire protocol (`/api-ws/v1/inference`) —
/// help.aliyun.com/zh/model-studio/fun-asr-client-events + fun-asr-server-events.
/// This is a *different* protocol from the retired OmniRealtime one on the sibling
/// `/api-ws/v1/realtime` path; getting the two confused is the failure this suite guards.
@Suite("QwenRunTaskASRProtocol")
struct QwenRunTaskASRProtocolTests {

    private func decodeJSON(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: - run-task

    @Test func runTaskCarriesTheDocumentedEnvelope() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1", model: "qwen-audio-3.0-asr-flash-streaming"))

        let header = root["header"] as? [String: Any]
        #expect(header?["action"] as? String == "run-task")
        #expect(header?["task_id"] as? String == "task-1")
        #expect(header?["streaming"] as? String == "duplex")

        let payload = root["payload"] as? [String: Any]
        #expect(payload?["task_group"] as? String == "audio")
        #expect(payload?["task"] as? String == "asr")
        #expect(payload?["function"] as? String == "recognition")
        #expect(payload?["model"] as? String == "qwen-audio-3.0-asr-flash-streaming")
        // `input` is required and must be present even when empty.
        #expect((payload?["input"] as? [String: Any])?.isEmpty == true)

        let parameters = payload?["parameters"] as? [String: Any]
        #expect(parameters?["format"] as? String == "pcm")
        #expect(parameters?["sample_rate"] as? Int == 16_000)
        #expect(parameters?["vocabulary"] == nil)
        #expect(parameters?["language_hints"] == nil)
    }

    @Test func runTaskAttachesInstantVocabularyAndLanguageHint() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1",
            model: "qwen-audio-3.0-asr-flash-streaming",
            hotwords: ["Westlaw", "厄洛替尼盐酸盐"],
            languageHint: "zh"))
        let parameters = (root["payload"] as? [String: Any])?["parameters"] as? [String: Any]

        #expect(parameters?["language_hints"] as? [String] == ["zh"])
        // weight 4 = 「明显偏好（推荐）」; the tuning doc warns 5 (强制偏好) misrecognises
        // similar-sounding words AS the hotword.
        #expect(parameters?["vocabulary"] as? [String: Int] == ["Westlaw": 4, "厄洛替尼盐酸盐": 4])
    }

    @Test func runTaskUsesPrecompiledVocabularyWhenNoInstantTermsExist() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1",
            model: "qwen-audio-3.0-asr-flash-streaming",
            precompiledVocabularyID: "vocab-curated-a1b2c3"))
        let parameters = (root["payload"] as? [String: Any])?["parameters"] as? [String: Any]

        #expect(parameters?["vocabulary_id"] as? String == "vocab-curated-a1b2c3")
        #expect(parameters?["vocabulary"] == nil)
    }

    /// The official contract says that when both fields are configured only instant hotwords take
    /// effect. The client therefore sends the complete current request vocabulary and omits the ID,
    /// preserving both curated terms and a just-learned mixed Chinese-English correction.
    @Test func instantVocabularySupersedesPrecompiledIDWithoutDroppingCuratedTerms() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1",
            model: "qwen-audio-3.0-asr-flash-streaming",
            hotwords: ["Westlaw", "法研 Metis", "Westlaw"],
            precompiledVocabularyID: "vocab-curated-a1b2c3"))
        let parameters = (root["payload"] as? [String: Any])?["parameters"] as? [String: Any]

        #expect(parameters?["vocabulary_id"] == nil)
        #expect(parameters?["vocabulary"] as? [String: Int] == ["Westlaw": 4, "法研 Metis": 4])
    }

    @Test func malformedPrecompiledIdentifierFailsOpenToInstantVocabulary() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1",
            model: "qwen-audio-3.0-asr-flash-streaming",
            hotwords: ["Metis"],
            precompiledVocabularyID: "not a vocabulary id"))
        let parameters = (root["payload"] as? [String: Any])?["parameters"] as? [String: Any]

        #expect(parameters?["vocabulary_id"] == nil)
        #expect(parameters?["vocabulary"] as? [String: Int] == ["Metis": 4])
    }

    @Test func runTaskCarriesContextMixedLanguageHeartbeatAndOmitsTuning() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1",
            model: "qwen-audio-3.0-asr-flash-streaming",
            languageHints: ["zh", "en"],
            context: ["上一句提到了 Metis。", "The repository is Responsay."],
            heartbeat: true))
        let payload = root["payload"] as? [String: Any]
        let parameters = payload?["parameters"] as? [String: Any]
        let context = (payload?["input"] as? [String: Any])?["context"] as? [[String: Any]]

        #expect(parameters?["language_hints"] as? [String] == ["zh", "en"])
        #expect(parameters?["heartbeat"] as? Bool == true)
        #expect(parameters?["semantic_punctuation_enabled"] == nil)
        #expect(parameters?["multi_threshold_mode_enabled"] == nil)
        #expect(parameters?["max_sentence_silence"] == nil)
        #expect(parameters?["speech_noise_threshold"] == nil)
        #expect(context?.count == 2)
        #expect(context?.first?["role"] as? String == "user")
        let firstContent = context?.first?["content"] as? [[String: Any]]
        #expect(firstContent?.first?["type"] as? String == "input_text")
        #expect(firstContent?.first?["text"] as? String == "上一句提到了 Metis。")
    }

    /// 即时热词 is documented for `qwen-audio-3.0-asr-flash-streaming` only; Fun-ASR-Realtime shares
    /// this protocol and endpoint but is not on that list. The live service accepts the field there
    /// rather than rejecting it (measured 2026-08-02), so this pins a docs-compliance choice, not a
    /// crash guard — see `QwenASRHotwords`.
    @Test func runTaskOmitsVocabularyForFunASRRealtime() {
        let root = decodeJSON(QwenRunTaskASRProtocol.runTask(
            taskID: "task-1", model: "fun-asr-realtime", hotwords: ["Westlaw"], languageHint: "zh"))
        let parameters = (root["payload"] as? [String: Any])?["parameters"] as? [String: Any]
        #expect(parameters?["vocabulary"] == nil)
        #expect(parameters?["language_hints"] as? [String] == ["zh"])
    }

    @Test func finishTaskCarriesTheDocumentedEnvelope() {
        let root = decodeJSON(QwenRunTaskASRProtocol.finishTask(taskID: "task-1"))
        let header = root["header"] as? [String: Any]
        #expect(header?["action"] as? String == "finish-task")
        #expect(header?["task_id"] as? String == "task-1")
        #expect(header?["streaming"] as? String == "duplex")
        let input = (root["payload"] as? [String: Any])?["input"] as? [String: Any]
        #expect(input?.isEmpty == true)
    }

    @Test func continueTaskUpdatesContextUsingTheDocumentedEnvelope() {
        let root = decodeJSON(QwenRunTaskASRProtocol.continueTask(
            taskID: "task-1", context: ["We just discussed Metis."]))
        let header = root["header"] as? [String: Any]
        #expect(header?["action"] as? String == "continue-task")
        #expect(header?["task_id"] as? String == "task-1")
        #expect(header?["streaming"] as? String == "duplex")

        let input = (root["payload"] as? [String: Any])?["input"] as? [String: Any]
        let context = input?["context"] as? [[String: Any]]
        let content = context?.first?["content"] as? [[String: Any]]
        #expect(context?.first?["role"] as? String == "user")
        #expect(content?.first?["type"] as? String == "input_text")
        #expect(content?.first?["text"] as? String == "We just discussed Metis.")
    }

    // MARK: - Server events

    @Test func decodesTaskStartedFinishedAndFailed() {
        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"task-started","attributes":{}},"payload":{}}
        """.utf8)) == .started)

        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"task-finished","attributes":{}},"payload":{"output":{}}}
        """.utf8)) == .finished)

        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"task-failed","error_code":"CLIENT_ERROR",
        "error_message":"request timeout after 23 seconds.","attributes":{}},"payload":{}}
        """.utf8)) == .failure("CLIENT_ERROR: request timeout after 23 seconds."))
    }

    @Test func decodesIntermediateAndFinalSentences() {
        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"result-generated"},
         "payload":{"output":{"sentence":{"sentence_id":1,"text":"好，我知","sentence_end":false}}}}
        """.utf8)) == .sentence(id: 1, text: "好，我知", isFinal: false))

        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"result-generated"},
         "payload":{"output":{"sentence":{"sentence_id":1,"text":"好，我知道了","sentence_end":true,
         "begin_time":170,"end_time":920}},"usage":{"duration":3}}}
        """.utf8)) == .sentence(id: 1, text: "好，我知道了", isFinal: true))
    }

    /// Heartbeats keep an idle socket alive and carry no transcript (`sentence_id` pinned to 0);
    /// the docs say to skip them. Folding one in would corrupt the transcript.
    @Test func skipsHeartbeatFrames() {
        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"task_id":"t","event":"result-generated"},
         "payload":{"output":{"sentence":{"sentence_id":0,"text":"","heartbeat":true,"sentence_end":false}}}}
        """.utf8)) == .ignored)
    }

    @Test func unknownAndMalformedFramesAreIgnored() {
        #expect(QwenRunTaskASRProtocol.decode(Data("{}".utf8)) == .ignored)
        #expect(QwenRunTaskASRProtocol.decode(Data("not json".utf8)) == .ignored)
        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"event":"something-else"},"payload":{}}
        """.utf8)) == .ignored)
        // result-generated without a sentence object must not crash or fabricate text.
        #expect(QwenRunTaskASRProtocol.decode(Data("""
        {"header":{"event":"result-generated"},"payload":{"output":{}}}
        """.utf8)) == .ignored)
    }
}

@Suite("QwenASRHotwords")
struct QwenASRHotwordsTests {

    /// 热词文本规范: ≤15 characters once any non-ASCII is present, ≤7 space-separated segments when
    /// pure ASCII. The 词典 allows 80-character entries, so over-long ones are dropped locally.
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
        #expect(QwenASRHotwords.supportsInstantVocabulary(model: "qwen-audio-3.0-asr-flash-streaming"))
        #expect(QwenASRHotwords.supportsInstantVocabulary(model: "qwen-audio-3.0-asr-flash"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "fun-asr-realtime"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "qwen3-asr-flash-realtime"))
        #expect(!QwenASRHotwords.supportsInstantVocabulary(model: "paraformer-realtime-v2"))
    }

    @Test func precompiledVocabularyIdentifierAcceptsAnOpaqueSingleSuffix() {
        #expect(QwenASRHotwords.normalizedVocabularyIdentifier(" vocab-deadbeef ") == "vocab-deadbeef")
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

    /// The Workspace ID becomes a DNS label, so anything but the documented `ws-…` shape must fall
    /// back to the generic host rather than be interpolated into a hostname.
    @Test func malformedWorkspaceIDCannotInjectAHost() {
        for bad in ["ws-abc123.evil.example", "https://evil.example", "evil.example",
                    "ws-", "ws-abc_123", "ws-abc/123", ""] {
            let endpoint = QwenRunTaskEndpoint(region: .china, workspaceID: bad)
            #expect(!endpoint.usesDedicatedHost, "\(bad) must not become a host")
            #expect(endpoint.url.absoluteString == "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        }
    }

    @Test func precompiledVocabularyBindingRequiresExactModelRegionWorkspaceAndFingerprint() {
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

    @Test func precompiledVocabularyBindingRejectsMalformedIdentifiersAndWorkspaceBindings() {
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
