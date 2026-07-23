import XCTest
@testable import ResponsayMac

final class CapabilityProbeRequestBuilderTests: XCTestCase {
    func testMimoASRProbeUsesRuntimeAuthHeaders() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "mimo",
            capability: .asr,
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1",
            apiKey: " tp-asr-key "
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://token-plan-cn.xiaomimimo.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "tp-asr-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testMimoTTSProbeUsesApiKeyHeaderOnly() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "mimo",
            capability: .tts,
            baseURL: "https://api.xiaomimimo.com/v1",
            apiKey: "mimo-tts-key"
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://api.xiaomimimo.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "mimo-tts-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testMimoLLMProbeUsesApiKeyHeaderOnly() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "mimo",
            capability: .llm,
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1",
            apiKey: "tp-llm-key"
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://token-plan-cn.xiaomimimo.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "tp-llm-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAICompatibleProbeUsesBearerHeader() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "openai",
            capability: .asr,
            baseURL: "https://api.openai.com/v1/chat/completions",
            apiKey: "sk-test"
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "api-key"))
    }

    func testNativeGeminiProbeUsesGoogleHeader() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "gemini",
            capability: .llm,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            apiKey: "AIza-test"
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testDoubaoLLMProbeUsesArkModelsEndpoint() throws {
        let request = try XCTUnwrap(CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "doubao",
            capability: .llm,
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            apiKey: "ark-test-key"
        ))

        XCTAssertEqual(request.url?.absoluteString, "https://ark.cn-beijing.volces.com/api/v3/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ark-test-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
    }

    func testVolcengineFlashASRDoesNotUseModelsProbe() throws {
        let request = CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "volcengine-flash",
            capability: .asr,
            baseURL: "https://openspeech.bytedance.com/api/v3",
            apiKey: "volc-app-key"
        )

        XCTAssertNil(request)
    }

    func testVolcengineTTSDoesNotUseModelsProbe() throws {
        // openspeech.bytedance.com has no /models endpoint — probing it 404s even though
        // synthesis works. The TTS card must validate locally, not via a models GET.
        XCTAssertFalse(CapabilityProbeRequestBuilder.supportsRemoteModelsRequest(
            providerId: "volcengine-tts", capability: .tts))

        let request = CapabilityProbeRequestBuilder.modelsRequest(
            providerId: "volcengine-tts",
            capability: .tts,
            baseURL: "https://openspeech.bytedance.com/api/v3",
            apiKey: "volc-tts-key"
        )

        XCTAssertNil(request)
    }
}
