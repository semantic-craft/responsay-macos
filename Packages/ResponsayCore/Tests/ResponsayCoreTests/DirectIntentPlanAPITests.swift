import Foundation
import Testing
@testable import ResponsayCore

// Every stub-backed test shares IntentStubURLProtocol's static state, so they all live in ONE
// serialized suite — separate `.serialized` suites would still run in parallel and race.
@Suite(.serialized)
struct DirectIntentPlanAPITests {
    @Test func fencedPlanIsUnwrappedToDecodablePlanData() async throws {
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion("```json\n\(validIntentPlanJSON())\n```")
        let api = DirectIntentPlanAPI(
            endpoint: intentQwenEndpoint(), session: intentStubSession())
        let data = try await api.compile(intentCorrectionInput())
        let plan = try JSONDecoder().decode(IntentPlan.self, from: data)
        #expect(plan.version == 1)
        #expect(plan.decision == .render)
        #expect(plan.units.count == 3)
        #expect(plan.supersessions.count == 1)
        #expect(IntentStubURLProtocol.requestURL?.absoluteString.hasSuffix("/chat/completions") == true)
    }

    @Test func thinkingIsForcedOffEvenWhenTheUserToggleIsOn() async throws {
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(validIntentPlanJSON())
        let api = DirectIntentPlanAPI(
            endpoint: intentQwenEndpoint(thinkingEnabled: true), session: intentStubSession())
        _ = try await api.compile(intentCorrectionInput())
        let body = try JSONSerialization.jsonObject(
            with: IntentStubURLProtocol.requestBody) as? [String: Any]
        #expect(body?["enable_thinking"] as? Bool == false)
        #expect(body?["stream"] as? Bool == false)
        #expect(body?["model"] as? String == "qwen-flash")
    }

    @Test func proseWithoutAJSONObjectThrowsWithoutLeakingProviderContent() async {
        let providerContent = "provider-response-must-not-enter-errors"
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(providerContent)
        let api = DirectIntentPlanAPI(
            endpoint: intentQwenEndpoint(), session: intentStubSession())
        do {
            _ = try await api.compile(intentCorrectionInput())
            Issue.record("Expected invalid provider prose to throw")
        } catch {
            #expect(!error.localizedDescription.contains(providerContent))
        }
    }

    @Test func httpErrorThrowsWithoutLeakingProviderBody() async {
        let providerBody = "provider-body-must-not-enter-errors"
        IntentStubURLProtocol.status = 500
        IntentStubURLProtocol.data = Data(providerBody.utf8)
        let api = DirectIntentPlanAPI(
            endpoint: intentQwenEndpoint(), session: intentStubSession())
        do {
            _ = try await api.compile(intentCorrectionInput())
            Issue.record("Expected provider HTTP failure to throw")
        } catch {
            #expect(!error.localizedDescription.contains(providerBody))
        }
    }

    @Test func leakedThinkBlockIsStrippedBeforeSlicing() async throws {
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(
            "<think>先找改口</think>\(validIntentPlanJSON())")
        let api = DirectIntentPlanAPI(
            endpoint: intentQwenEndpoint(), session: intentStubSession())
        let data = try await api.compile(intentCorrectionInput())
        let plan = try JSONDecoder().decode(IntentPlan.self, from: data)
        #expect(plan.decision == .render)
    }

    // MARK: - Pipeline end-to-end over the stubbed cloud

    @Test func stubbedCloudNearCorrectionCompilesToInsertableWinner() async {
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(validIntentPlanJSON())
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(
                endpoint: intentQwenEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript,
            locale: .chinese,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
    }

    @Test func extraUnknownFieldFromTheProviderIsSafeUnavailable() async {
        // A "finalText" the model invented must never bypass the source renderer.
        let poisoned = validIntentPlanJSON().replacingOccurrences(
            of: "{\"version\": 1,",
            with: "{\"version\": 1, \"finalText\": \"我编的正文\",")
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(poisoned)
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(
                endpoint: intentQwenEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript,
            locale: .chinese,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .invalidPlan))
    }

    @Test func providerProseIsSafeUnavailableNotRawInsert() async {
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion("周四开会")
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(
                endpoint: intentQwenEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript,
            locale: .chinese,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        // Provider prose with no plan JSON is a *bad response* (坏响应), not a provider
        // outage — #559 classification tells the two apart so the capsule can say which.
        #expect(outcome == .safeUnavailable(reason: .invalidPlan))
    }

    // MARK: - #566 local strict-plan route (same compiler, no cloud fallback)

    @Test func localEndpointSendsJSONObjectResponseFormat_cloudDoesNot() async throws {
        // Local: json_object mode is sent so a small local model emits parseable JSON.
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(validIntentPlanJSON())
        _ = try await DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: intentStubSession())
            .compile(intentCorrectionInput())
        let localBody = try JSONSerialization.jsonObject(with: IntentStubURLProtocol.requestBody) as? [String: Any]
        #expect((localBody?["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(IntentStubURLProtocol.requestURL?.host == "localhost")   // never a cloud host

        // Cloud: the same compiler omits response_format (several providers 400 on it).
        IntentStubURLProtocol.data = intentCompletion(validIntentPlanJSON())
        _ = try await DirectIntentPlanAPI(endpoint: intentQwenEndpoint(), session: intentStubSession())
            .compile(intentCorrectionInput())
        let cloudBody = try JSONSerialization.jsonObject(with: IntentStubURLProtocol.requestBody) as? [String: Any]
        #expect(cloudBody?["response_format"] == nil)
    }

    @Test func localValidPlanInsertsAndContactsOnlyLocalhost() async {
        IntentStubURLProtocol.requestURL = nil
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion(validIntentPlanJSON())
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript, locale: .chinese,
            allowedContext: nil, routePolicy: .injectedCompiler)
        // Same contract as cloud → identical insertable outcome.
        #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
        #expect(IntentStubURLProtocol.requestURL?.host == "localhost")
    }

    @Test func localHTTP4xxIsCapabilityUnsupportedAndStaysLocal() async {
        // A local runner's 4xx (model not installed / response_format unsupported) is a capability
        // fault, not a transient outage, and it must never fall back to the cloud.
        IntentStubURLProtocol.requestURL = nil
        IntentStubURLProtocol.status = 404
        IntentStubURLProtocol.data = Data("model not found".utf8)
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript, locale: .chinese,
            allowedContext: nil, routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .capabilityUnsupported))
        #expect(IntentStubURLProtocol.requestURL?.host == "localhost")   // zero cloud requests
    }

    @Test func localHTTP5xxStaysCompilerFailedRetryableNotCapability() async {
        // A transient local 5xx is retryable `compilerFailed`, distinct from a capability fault.
        IntentStubURLProtocol.requestURL = nil
        IntentStubURLProtocol.status = 503
        IntentStubURLProtocol.data = Data("service unavailable".utf8)
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript, locale: .chinese,
            allowedContext: nil, routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .compilerFailed))
        #expect(IntentStubURLProtocol.requestURL?.host == "localhost")
    }

    @Test func localProseIsInvalidPlanFailClosedNoCloud() async {
        // Plain text from a local model fails closed (no plain-text passthrough), same as cloud.
        IntentStubURLProtocol.requestURL = nil
        IntentStubURLProtocol.status = 200
        IntentStubURLProtocol.data = intentCompletion("周四开会")
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript, locale: .chinese,
            allowedContext: nil, routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .invalidPlan))
        #expect(IntentStubURLProtocol.requestURL?.host == "localhost")
    }

    @Test func unconfiguredEndpointIsSafeUnavailableWithZeroNetworkCalls() async {
        IntentStubURLProtocol.requestURL = nil
        let noKey = LLMEndpoint(
            providerId: "qwen",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-flash",
            apiKey: nil)
        let pipeline = IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: noKey, session: intentStubSession()))
        let outcome = await pipeline.compile(
            finalTranscript: intentCorrectionTranscript,
            locale: .chinese,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        // No key never reaches the network — and it reads as "not set up" (无 Key), not a
        // provider outage. (#559: 无 Key vs provider 不可用 are separate capsule states.)
        #expect(outcome == .safeUnavailable(reason: .compilerUnavailable))
        #expect(IntentStubURLProtocol.requestURL == nil)
    }
}
