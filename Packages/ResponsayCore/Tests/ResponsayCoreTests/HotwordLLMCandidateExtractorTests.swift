import Testing
import Foundation
@testable import ResponsayCore

@Suite struct HotwordLLMCandidateExtractorTests {
    @Test func localRequestUsesLocalEndpointWithoutCloudKey() throws {
        let endpoint = LLMEndpoint(
            providerId: "ollama",
            baseURL: "http://localhost:11434/v1",
            model: "gemma4:e4b",
            apiKey: nil)
        let context = HotwordCorrectionContext(
            insertedText: "问一下沈眼秋",
            userFinalText: "问一下沈砚秋",
            appName: "Notes",
            windowTitle: "项目群")

        let request = try HotwordLLMRequestBuilder.makeRequest(
            endpoint: endpoint,
            source: .localModel,
            substitutions: EditDelta.compute(
                inserted: context.insertedText, userFinal: context.userFinalText).substitutions)

        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let bodyText = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body["response_format"] != nil)
        #expect(bodyText.contains("沈眼秋"))
        #expect(bodyText.contains("沈砚秋"))
        #expect(!bodyText.contains("audio_context"))
        #expect(!bodyText.contains("apiKey"))
        #expect(!bodyText.contains("sk-"))
    }

    @Test func cloudRequestKeepsKeyOutOfPayload() throws {
        let endpoint = LLMEndpoint(
            providerId: "qwen",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen3.6-flash",
            apiKey: "sk-secret")
        let context = HotwordCorrectionContext(
            insertedText: "用 responsay",
            userFinalText: "用 Responsay",
            appName: "Safari",
            windowTitle: "设置")
        let request = try HotwordLLMRequestBuilder.makeRequest(
            endpoint: endpoint,
            source: .cloudBYOK,
            substitutions: EditDelta.compute(
                inserted: context.insertedText, userFinal: context.userFinalText).substitutions)

        let bodyText = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
        #expect(!bodyText.contains("sk-secret"))
        #expect(!bodyText.contains("recording"))
        #expect(!bodyText.contains("history"))
    }

    /// Regression for the dictionary-pollution bug: the request must carry ONLY the words the user
    /// actually changed (cloud→Claude), never entity-shaped tokens that merely sat unchanged in the
    /// field or in the app/window name (librime, NeuralRanker, responsay.com, Famo-1.1.pkg). Sending
    /// the whole before/after text is what let those get "learned" though never spoken.
    @Test func onlyChangedWordsReachTheModel() throws {
        let context = HotwordCorrectionContext(
            insertedText: "我在写 librime 和 NeuralRanker，把 cloud 改一下",
            userFinalText: "我在写 librime 和 NeuralRanker，把 Claude 改一下",
            appName: "responsay.com",
            windowTitle: "Famo-1.1.pkg")
        let request = try HotwordLLMRequestBuilder.makeRequest(
            endpoint: Self.localEndpoint,
            source: .cloudBYOK,
            substitutions: EditDelta.compute(
                inserted: context.insertedText, userFinal: context.userFinalText).substitutions)

        let bodyText = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyText.contains("cloud"))
        #expect(bodyText.contains("Claude"))
        #expect(!bodyText.contains("librime"))
        #expect(!bodyText.contains("NeuralRanker"))
        #expect(!bodyText.contains("responsay.com"))
        #expect(!bodyText.contains("Famo-1.1.pkg"))
    }

    /// An edit with no word substitution (a pure append — still typing) is not a term correction,
    /// so the LLM is never called: no wasted request, no chance to harvest unspoken tokens. `execute`
    /// throws if reached, so a skipped call leaves `.lowConfidence` while a reached one would be `.failed`.
    @Test func editWithoutSubstitutionSkipsTheModel() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .cloudBYOK,
            execute: { _ in throw MockProviderError.unavailable })

        let result = await extractor.extractWithStatus(HotwordCorrectionContext(
            insertedText: "draft the section",
            userFinalText: "draft the section about pricing",
            appName: "Notes",
            windowTitle: "项目群"))

        #expect(result.status == .lowConfidence)
        #expect(result.candidates.isEmpty)
    }

    @Test func successfulResponseReturnsCandidateWithSource() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .localModel,
            execute: { _ in
                #"{"candidates":[{"term":"沈砚秋","confidence":0.94,"reason":"用户把人名改成该写法"}]}"#
            })

        let result = await extractor.extractWithStatus(Self.context)

        #expect(result.status == .ready)
        #expect(result.candidates == [
            HotwordCandidateProposal(
                term: "沈砚秋",
                source: .localModel,
                confidence: 0.94,
                reason: "用户把人名改成该写法",
                appName: "Notes",
                windowTitle: "项目群")
        ])
    }

    @Test func malformedJSONFailsClosed() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .localModel,
            execute: { _ in "not json" })

        let result = await extractor.extractWithStatus(Self.context)

        #expect(result.status == .malformedResponse)
        #expect(result.candidates.isEmpty)
    }

    @Test func lowConfidenceFailsClosed() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .localModel,
            execute: { _ in #"{"candidates":[{"term":"沈砚秋","confidence":0.5,"reason":"弱"}]}"# })

        let result = await extractor.extractWithStatus(Self.context)

        #expect(result.status == .lowConfidence)
        #expect(result.candidates.isEmpty)
    }

    @Test func timeoutFailsClosed() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .localModel,
            execute: { _ in throw HotwordCandidateExtractionError.timedOut })

        let result = await extractor.extractWithStatus(Self.context)

        #expect(result.status == .timedOut)
        #expect(result.candidates.isEmpty)
    }

    @Test func providerFailureFailsClosed() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: Self.localEndpoint,
            source: .cloudBYOK,
            execute: { _ in throw MockProviderError.unavailable })

        let result = await extractor.extractWithStatus(Self.context)

        if case .failed = result.status {
            #expect(result.candidates.isEmpty)
        } else {
            Issue.record("Expected failed status, got \(result.status)")
        }
    }

    @Test func unconfiguredEndpointFailsClosed() async {
        let extractor = DirectHotwordLLMCandidateExtractor(
            endpoint: LLMEndpoint(providerId: "qwen", baseURL: "", model: "", apiKey: nil),
            source: .cloudBYOK,
            execute: { _ in "should not run" })

        let result = await extractor.extractWithStatus(Self.context)

        #expect(result.status == .notConfigured)
        #expect(result.candidates.isEmpty)
    }

    private static let localEndpoint = LLMEndpoint(
        providerId: "ollama",
        baseURL: "http://localhost:11434/v1",
        model: "gemma4:e4b",
        apiKey: nil)

    private static let context = HotwordCorrectionContext(
        insertedText: "问一下沈眼秋",
        userFinalText: "问一下沈砚秋",
        appName: "Notes",
        windowTitle: "项目群")

    private enum MockProviderError: Error {
        case unavailable
    }
}
