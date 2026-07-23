import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S4 — the aggregated bad-response & degradation matrix (Testing Decisions 10–11): one
/// readable enumeration of EVERY failure class, each asserted to reach a non-insertable outcome.
/// No provider raw response can ever bypass the safety spine into an auto-insert.
///
/// Injection is fixture-`Data` / structural plan / thrown error — never the shared HTTP stub — so
/// this suite never races the serialized `DirectIntentPlanAPITests`, which remains the canonical
/// owner of the real transport→error mapping (status codes) and the zero-cloud-request proof
/// (that local endpoints only ever contact localhost). The privacy suite re-proves zero-cloud.
struct IntentBadResponseMatrixTests {

    private struct ThrowingIntentCompiler: IntentPlanCompiler {
        let error: any Error
        func compile(_ input: IntentCompilerInput) async throws -> Data { throw error }
    }

    private static func compile(
        _ compiler: any IntentPlanCompiler, transcript: String = "A",
        grounding: IntentGroundingSources = .empty
    ) async -> IntentCompilationOutcome {
        await IntentCompilationPipeline(compiler: compiler).compile(
            finalTranscript: transcript, locale: .chinese,
            allowedContext: nil, routePolicy: .injectedCompiler, grounding: grounding)
    }

    // MARK: - Malformed / poisoned response bodies → invalidPlan (never insertable)

    static let malformedBodies: [(name: String, json: String)] = [
        ("empty response", ""),
        ("empty json object", "{}"),
        ("pure text, no JSON", "unchecked plain text 周四开会"),
        ("truncated / broken JSON", #"{"version":1,"decision":"#),
        ("missing required field (units)", #"{"version":1,"decision":"noIntentControl","supersessions":[]}"#),
        ("unknown top-level field", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[],"mystery":true}"#),
        ("unsupported version", #"{"version":9,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("unknown source id", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"ghost","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("UTF-16 range out of bounds", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":9},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("exact quote mismatch", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"Z"},"role":"content"}],"supersessions":[]}"#),
        ("invented free final text", #"{"version":1,"decision":"render","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[],"finalText":"我编的正文"}"#)
    ]

    @Test(arguments: malformedBodies)
    func malformedResponseIsSafeUnavailableInvalidPlan(_ row: (name: String, json: String)) async {
        let outcome = await Self.compile(FixtureIntentCompiler { _ in Data(row.json.utf8) })
        #expect(outcome == .safeUnavailable(reason: .invalidPlan), "\(row.name)")
    }

    // MARK: - Structurally valid JSON, semantically illegal plans → invalidPlan

    @Test func illegalRoleAndSupersessionShapesAreRejected() async {
        // cue that isn't a correction (misplaced role)
        let cueNotCorrection = FixtureIntentCompiler { input in
            let s = input.sourceUnits
            return try JSONEncoder().encode(IntentPlan(version: 1, decision: .render,
                units: [.init(source: .init(s[0]), role: .content),
                        .init(source: .init(s[1]), role: .content),      // should be .correction
                        .init(source: .init(s[2]), role: .content)],
                supersessions: [.init(winner: .init(s[2]), loser: .init(s[0]), cue: .init(s[1]))]))
        }
        // cyclic + reused cue supersession
        let cyclic = FixtureIntentCompiler { input in
            let s = input.sourceUnits
            return try JSONEncoder().encode(IntentPlan(version: 1, decision: .render,
                units: [.init(source: .init(s[0]), role: .content),
                        .init(source: .init(s[1]), role: .correction),
                        .init(source: .init(s[2]), role: .content)],
                supersessions: [.init(winner: .init(s[2]), loser: .init(s[0]), cue: .init(s[1])),
                                .init(winner: .init(s[0]), loser: .init(s[2]), cue: .init(s[1]))]))
        }
        #expect(await Self.compile(cueNotCorrection, transcript: "甲，不对，丙") == .safeUnavailable(reason: .invalidPlan))
        #expect(await Self.compile(cyclic, transcript: "旧值，不对，新值") == .safeUnavailable(reason: .invalidPlan))
    }

    @Test func illegalStructureAndEntityPlansAreRejected() async {
        let clue = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"
        @Sendable func cluePlan(_ input: IntentCompilerInput, entities: [String]) -> IntentPlan {
            IntentPlan(version: 1, decision: .render,
                units: [.init(source: .init(input.sourceUnits[0]), role: .content),
                        .init(source: .init(input.sourceUnits[1]), role: .grounding),
                        .init(source: .init(input.sourceUnits[2]), role: .content)],
                supersessions: [], entities: entities)
        }
        // unknown candidate id — the only way to "invent" an entity — is structurally invalid.
        let unknownEntity = FixtureIntentCompiler { input in
            try JSONEncoder().encode(cluePlan(input, entities: ["entity-9999"])) }
        // render plan acknowledges a grounding clue but resolves nothing → the clue would vanish.
        let unresolvedClue = FixtureIntentCompiler { input in
            try JSONEncoder().encode(cluePlan(input, entities: [])) }
        // structure drops a renderable unit (conservation violation)
        let droppedUnit = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(version: 1, decision: .render,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: [],
                structure: IntentPlanStructure(kind: .bulletList,
                    groups: [["source-0000"], ["source-0001"]]))) }              // 缺 source-0002
        // structure smuggles a non-renderable side note back into the output
        let noteSmuggled = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(version: 1, decision: .render,
                units: [.init(source: .init(input.sourceUnits[0]), role: .content),
                        .init(source: .init(input.sourceUnits[1]), role: .sideNote),
                        .init(source: .init(input.sourceUnits[2]), role: .content)],
                supersessions: [],
                structure: IntentPlanStructure(kind: .bulletList,
                    groups: [["source-0000"], ["source-0001"], ["source-0002"]]))) }

        #expect(await Self.compile(unknownEntity, transcript: clue) == .safeUnavailable(reason: .invalidPlan))
        // #575: unresolved grounding with a non-empty table degrades to candidate-confirm
        // review (never an insert; a dead blocked card helps nobody).
        let unresolvedOutcome = await Self.compile(unresolvedClue, transcript: clue)
        guard case .needsReview(.unexplainedGroundingCue, _) = unresolvedOutcome else {
            Issue.record("expected candidate-confirm review, got \(unresolvedOutcome)")
            return
        }
        #expect(await Self.compile(droppedUnit, transcript: "第一，第二，第三") == .safeUnavailable(reason: .invalidPlan))
        #expect(await Self.compile(noteSmuggled, transcript: "备份数据，这句不用写，通知客户") == .safeUnavailable(reason: .invalidPlan))
    }

    // MARK: - Transport / lifecycle errors → classified non-insertable outcome

    @Test func thrownTransportAndLifecycleErrorsClassifyToNonInsertableOutcomes() async {
        // `any Error` isn't Sendable, so this table is walked inside the test rather than via
        // @Test(arguments:). Each row exercises the pipeline's content-free error classification.
        let rows: [(name: String, error: any Error, expected: IntentUnavailableReason)] = [
            ("provider timeout (self-classified)", IntentCompilerFailure(.providerTimeout), .providerTimeout),
            ("capability unsupported (schema)", IntentCompilerFailure(.capabilityUnsupported), .capabilityUnsupported),
            ("cancelled", CancellationError(), .cancelled),
            ("cloud/local unreachable (network)", LLMError.network("unreachable"), .compilerFailed),
            ("provider HTTP error", LLMError.http(status: 503, body: "x"), .compilerFailed),
            ("no key / not configured", LLMError.notConfigured, .compilerUnavailable),
            ("empty content from transport", LLMError.emptyContent, .invalidPlan),
            ("bad JSON envelope from transport", LLMError.badJSON("x"), .invalidPlan)
        ]
        for row in rows {
            let outcome = await Self.compile(ThrowingIntentCompiler(error: row.error))
            #expect(outcome == .safeUnavailable(reason: row.expected), "\(row.name)")
            if case .insertable = outcome { Issue.record("\(row.name): a bad response reached auto-insert") }
        }
    }

    // MARK: - Empty / preformed source → never compiled, never inserted

    @Test func emptySourceAndUnavailableRouteNeverInsert() async {
        // Empty transcript = no source to compile.
        #expect(await Self.compile(FixtureIntentCompiler { _ in Data() }, transcript: "")
            == .safeUnavailable(reason: .invalidSource))
        // No authorized compiler route at all.
        let noRoute = await IntentCompilationPipeline(compiler: nil).compile(
            finalTranscript: "A", locale: .chinese, allowedContext: nil, routePolicy: .unavailable)
        #expect(noRoute == .safeUnavailable(reason: .compilerUnavailable))
    }
}
