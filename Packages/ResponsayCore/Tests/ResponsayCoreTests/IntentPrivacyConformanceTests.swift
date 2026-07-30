import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S7 — the aggregated privacy release gate (Testing Decisions 20–21 / AC9 / AC12): every
/// intent-privacy promise, asserted in one place. New here: screen-context-off keeps screen fields
/// out of the compiler input, a local route contacts only localhost, the review sidecar surfaces
/// only the sanitized draft, and an unconfirmed/rejected result learns nothing. History-zero-raw
/// and cancel-clears-session are re-asserted (their canonical owners are IntentHistoryPrivacyTests
/// / IntentAwareOrchestrationTests).

// Own URLProtocol subclass + static state so this suite never races the other LLM stub suites.
// Records EVERY intercepted request URL (not just the last): the zero-cloud gate must prove that
// no request left the device, so a hypothetical cloud preflight BEFORE the localhost call is caught.
private final class PrivacyStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var requestURLs = [URL]()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let url = request.url { Self.requestURLs.append(url) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func privacyStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PrivacyStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// Captures the `allowedContext` the pipeline forwards to the compiler.
private actor ContextRecordingCompiler: IntentPlanCompiler {
    private(set) var contexts = [ExpressionContext?]()
    func compile(_ input: IntentCompilerInput) async throws -> Data {
        contexts.append(input.allowedContext)
        return try JSONEncoder().encode(IntentPlan(
            version: 1, decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: []))
    }
    func captured() -> [ExpressionContext?] { contexts }
}

struct IntentPrivacyConformanceTests {

    // MARK: - Screen context off ⇒ zero screen fields reach the compiler (AC9)

    // The Core seam contract: the pipeline forwards EXACTLY the `allowedContext` it is handed and
    // fabricates nothing. The app-layer toggle turns screen context off by handing `nil` (its
    // contextProvider returns nil); the real-device end-to-end "toggle off ⇒ zero fields outbound"
    // is #568. Here: nil in ⇒ nil to the compiler; fields in ⇒ exactly those fields, never invented.
    @Test func screenContextOff_noScreenFieldsReachTheCompiler() async {
        let recorder = ContextRecordingCompiler()
        _ = await IntentCompilationPipeline(compiler: recorder).compile(
            finalTranscript: "把结论发出去", locale: .chinese,
            allowedContext: nil,                          // app hands nil when the toggle is OFF
            routePolicy: .injectedCompiler)
        #expect(await recorder.captured() == [nil], "screen-off (nil context) must forward no context")

        // Positive control: with a context, exactly the allowed fields pass — nothing fabricated.
        let onRecorder = ContextRecordingCompiler()
        let allowed = ExpressionContext(appName: "Mail", textBeforeCursor: "Dear")
        _ = await IntentCompilationPipeline(compiler: onRecorder).compile(
            finalTranscript: "把结论发出去", locale: .chinese,
            allowedContext: allowed, routePolicy: .injectedCompiler)
        #expect(await onRecorder.captured() == [allowed])
    }

    // MARK: - Local route ⇒ zero cloud requests (AC9)

    @Test func localSelection_contactsOnlyLocalhostNeverCloud() async {
        PrivacyStubURLProtocol.requestURLs = []
        PrivacyStubURLProtocol.data = intentChatCompletion(validIntentPlanJSON())
        let outcome = await IntentCompilationPipeline(
            compiler: DirectIntentPlanAPI(endpoint: intentLocalEndpoint(), session: privacyStubSession()))
            .compile(finalTranscript: intentCorrectionTranscript, locale: .chinese,
                     allowedContext: nil, routePolicy: .injectedCompiler)
        #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
        // EVERY request the local route issued stayed on the device — not just the last one.
        #expect(!PrivacyStubURLProtocol.requestURLs.isEmpty, "the local route must actually issue its request")
        #expect(PrivacyStubURLProtocol.requestURLs.allSatisfy { $0.host == "localhost" },
                "no request may leave the device: \(PrivacyStubURLProtocol.requestURLs.map(\.host))")
    }

    // MARK: - Review sidecar surfaces only the sanitized draft, never the raw clue (AC12)

    @Test func reviewProposal_surfacesSanitizedDraftNotRawControlSpeech() async {
        let clue = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"
        let compiler = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .render,
                units: [.init(source: .init(input.sourceUnits[0]), role: .content),
                        .init(source: .init(input.sourceUnits[1]), role: .grounding),
                        .init(source: .init(input.sourceUnits[2]), role: .content)],
                supersessions: [], entities: [input.entityCandidates[0].id]))
        }
        let outcome = await IntentCompilationPipeline(compiler: compiler).compile(
            finalTranscript: clue, locale: .chinese, allowedContext: nil,
            routePolicy: .injectedCompiler,
            grounding: IntentGroundingSources(aliases: [.init(surface: "贺正杰", canonical: "何政杰")]))
        guard case let .needsReview(_, proposal?) = outcome else {
            Issue.record("expected contested-entity review, got \(outcome)")
            return
        }
        // The safe draft leaves the contested span as spoken; the clue clause never surfaces.
        let draft = proposal.content.sanitizedDraft ?? ""
        #expect(draft == "贺正杰，请转告他")
        #expect(!draft.contains("如何的何"))
        #expect(!draft.contains("杰出的杰"))
    }

    // MARK: - Unconfirmed / rejected results learn nothing (AC9)

    @Test func unconfirmedOrRejectedOutcomes_authorizeNoLearning() async {
        let clue = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"
        let compiler = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .render,
                units: [.init(source: .init(input.sourceUnits[0]), role: .content),
                        .init(source: .init(input.sourceUnits[1]), role: .grounding),
                        .init(source: .init(input.sourceUnits[2]), role: .content)],
                supersessions: [], entities: [input.entityCandidates[0].id]))
        }
        let outcome = await IntentCompilationPipeline(compiler: compiler).compile(
            finalTranscript: clue, locale: .chinese, allowedContext: nil,
            routePolicy: .injectedCompiler,
            grounding: IntentGroundingSources(aliases: [.init(surface: "贺正杰", canonical: "何政杰")]))
        guard case let .needsReview(_, proposal?) = outcome else {
            Issue.record("expected review proposal")
            return
        }
        let candidateID = proposal.content.candidates[0].id

        // Positive control — learnable() is LIVE: confirming this grounded candidate DOES insert and
        // DOES authorize the surface→canonical alias. Without this, the negatives below would also
        // pass against a dead (always-nil) function.
        let confirmed = IntentReviewResolver.confirm(candidateID: candidateID, in: proposal)
        guard case .insertable = confirmed else {
            Issue.record("expected the confirm to produce an insertable result")
            return
        }
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: candidateID, in: proposal, outcome: confirmed) != nil)

        // A result that did not become insertable (still in review, or safe-unavailable/cancelled)
        // authorizes NO alias learning — model candidates and unconfirmed names never reach the ledger.
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: candidateID, in: proposal,
            outcome: .needsReview(reason: .ambiguousEntityCandidates)) == nil)
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: candidateID, in: proposal,
            outcome: .safeUnavailable(reason: .cancelled)) == nil)
    }

    // MARK: - Content-free outcomes (AC12)

    @Test func externalOutcomeReasonsCarryNoTranscriptText() async {
        // safe-unavailable / needs-review reasons are enums — no request/response text can ride them.
        let badResponse = await IntentCompilationPipeline(
            compiler: FixtureIntentCompiler { _ in Data("私密旁注 leak me".utf8) })
            .compile(finalTranscript: "私密旁注 leak me", locale: .chinese,
                     allowedContext: nil, routePolicy: .injectedCompiler)
        #expect(badResponse == .safeUnavailable(reason: .invalidPlan))
        if case let .safeUnavailable(reason) = badResponse {
            #expect(!"\(reason)".contains("leak"))   // the reason is a bare category
        }
    }

    // MARK: - History zero raw + cancel clears session (aggregate re-assert)

    @MainActor
    private func makeVM(
        transcript: String, compiler: any IntentPlanCompiler
    ) -> (QuickCaptureViewModel, MockTextInserter, FileCaptureStore) {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = transcript
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        let vm = QuickCaptureViewModel(
            speech: speech, coach: MockCoachAPI(), store: store, inserter: inserter,
            intentCompiler: compiler, intentRoutePolicyProvider: { .injectedCompiler })
        vm.locale = .chinese
        return (vm, inserter, store)
    }

    @Test @MainActor func intentInsert_persistsNoRawTranscript() async throws {
        let compiler = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .noIntentControl,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: []))
        }
        let (vm, inserter, store) = makeVM(transcript: "开会时间照旧", compiler: compiler)
        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(inserter.inserted == ["开会时间照旧"])
        let saved = try #require(try store.recent(10).first)
        #expect(saved.sourceText == nil)                 // Intent-aware history keeps NO raw utterance
        #expect(saved.intentOutcome == .inserted)
    }

    @Test @MainActor func cancelDuringReview_clearsAllSessionSensitiveState() async throws {
        let needsReview = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .needsReview,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: []))
        }
        let (vm, _, store) = makeVM(transcript: "这个到底写不写", compiler: needsReview)
        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        #expect(vm.phase == .review)

        vm.discard()                                     // the review-cancel action (#559/#37)
        #expect(vm.phase == .idle)
        #expect(vm.transcript.isEmpty)
        #expect(vm.captureResult == nil)
        #expect(vm.intentReviewProposal == nil)
        #expect(vm.intentCaptureStartSnapshot == nil)
        #expect(try store.recent(10).isEmpty)            // a cancelled review persists nothing
    }
}
