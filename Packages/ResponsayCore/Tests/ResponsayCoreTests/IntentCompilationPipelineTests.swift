import Foundation
import Testing
@testable import ResponsayCore

struct FixtureIntentCompiler: IntentPlanCompiler {
    let response: @Sendable (IntentCompilerInput) throws -> Data

    func compile(_ input: IntentCompilerInput) async throws -> Data {
        try response(input)
    }
}

@Test func intentCompilation_resolvesNearbyCorrectionFromVerifiedSourcePlan() async {
    let compiler = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        #expect(sources.map(\.originalText) == ["周三开会，", "不对，", "周四开会"])

        let plan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(
                    winner: .init(sources[2]),
                    loser: .init(sources[0]),
                    cue: .init(sources[1]))
            ])
        return try JSONEncoder().encode(plan)
    }
    let pipeline = IntentCompilationPipeline(compiler: compiler)

    let outcome = await pipeline.compile(
        finalTranscript: "周三开会，不对，周四开会",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
}

@Test func intentCompilation_rejectsUnknownFieldInsideUTF16Range() async {
    let compiler = FixtureIntentCompiler { _ in
        Data(#"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1,"extra":true},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#.utf8)
    }
    let pipeline = IntentCompilationPipeline(compiler: compiler)

    let outcome = await pipeline.compile(
        finalTranscript: "A",
        locale: .english,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(outcome == .safeUnavailable(reason: .invalidPlan))
}

@Test func intentSourceSegmentation_preservesOriginalAndGlobalUTF16Ranges() {
    let units = IntentSourceSegmenter.segment("  😀A，B  ")

    #expect(units.map(\.originalText) == ["  😀A，", "B  "])
    #expect(units.map(\.utf16Range) == [
        IntentSourceRange(location: 0, length: 6),
        IntentSourceRange(location: 6, length: 3)
    ])
    #expect(units.map(\.id) == ["source-0000", "source-0001"])
    #expect(units[0].comparisonKey == "😀a,")
}

@Test func intentCompilation_acceptsExplicitNoIntentControlPlan() async {
    let compiler = FixtureIntentCompiler { input in
        let plan = IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: [])
        return try JSONEncoder().encode(plan)
    }
    let pipeline = IntentCompilationPipeline(compiler: compiler)

    let outcome = await pipeline.compile(
        finalTranscript: "  Keep 😀 exactly. ",
        locale: .english,
        allowedContext: ExpressionContext(appName: "Notes"),
        routePolicy: .injectedCompiler)

    #expect(outcome == .insertable(text: "  Keep 😀 exactly. ", route: .ordinaryPolished))
}

@Test func intentCompilation_rejectsInvalidPlanMatrix() async {
    let cases: [(String, String)] = [
        ("missing required field", #"{"version":1,"decision":"noIntentControl","units":[]}"#),
        ("unknown top-level field", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[],"extra":true}"#),
        ("unsupported version", #"{"version":2,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("unknown source id", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"missing","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("UTF-16 range out of bounds", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":2},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#),
        ("exact quote mismatch", #"{"version":1,"decision":"noIntentControl","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"B"},"role":"content"}],"supersessions":[]}"#),
        ("plain-text fallback", "unchecked plain text"),
        ("free final text", #"{"version":1,"decision":"render","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[],"finalText":"invented"}"#)
    ]

    for (name, json) in cases {
        let pipeline = IntentCompilationPipeline(
            compiler: FixtureIntentCompiler { _ in Data(json.utf8) })
        let outcome = await pipeline.compile(
            finalTranscript: "A",
            locale: .english,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .invalidPlan), "\(name)")
    }
}

@Test func intentCompilation_withoutAuthorizedCompilerRoute_isSafeUnavailable() async {
    let outcome = await IntentCompilationPipeline(compiler: nil).compile(
        finalTranscript: "A",
        locale: .english,
        allowedContext: nil,
        routePolicy: .unavailable)

    #expect(outcome == .safeUnavailable(reason: .compilerUnavailable))
}

@Test func intentCompilation_rejectsCyclicSupersessionRelationship() async {
    let compiler = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        let plan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1])),
                .init(winner: .init(sources[0]), loser: .init(sources[2]), cue: .init(sources[1]))
            ])
        return try JSONEncoder().encode(plan)
    }
    let pipeline = IntentCompilationPipeline(compiler: compiler)

    let outcome = await pipeline.compile(
        finalTranscript: "旧值，不对，新值",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(outcome == .safeUnavailable(reason: .invalidPlan))
}

@Test func intentCompilation_rejectsAmbiguousSupersessionAndOrphanCorrection() async {
    let ambiguous = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        return try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content),
                .init(source: .init(sources[3]), role: .correction),
                .init(source: .init(sources[4]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1])),
                .init(winner: .init(sources[4]), loser: .init(sources[0]), cue: .init(sources[3]))
            ]))
    }
    let orphanCorrection = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        return try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: []))
    }

    let ambiguousOutcome = await IntentCompilationPipeline(compiler: ambiguous).compile(
        finalTranscript: "A，不对，B，改口，C",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)
    let orphanOutcome = await IntentCompilationPipeline(compiler: orphanCorrection).compile(
        finalTranscript: "A，不对，B",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(ambiguousOutcome == .safeUnavailable(reason: .invalidPlan))
    #expect(orphanOutcome == .safeUnavailable(reason: .invalidPlan))
}

@Test func intentCompilation_rejectsReusedOrOutOfOrderCorrectionCue() async {
    let reusedCue = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        return try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content),
                .init(source: .init(sources[3]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1])),
                .init(winner: .init(sources[3]), loser: .init(sources[2]), cue: .init(sources[1]))
            ]))
    }
    let outOfOrderCue = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        return try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .correction),
                .init(source: .init(sources[1]), role: .content),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[1]), cue: .init(sources[0]))
            ]))
    }

    let reusedOutcome = await IntentCompilationPipeline(compiler: reusedCue).compile(
        finalTranscript: "A，不对，B，C",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)
    let orderOutcome = await IntentCompilationPipeline(compiler: outOfOrderCue).compile(
        finalTranscript: "不对，A，B",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(reusedOutcome == .safeUnavailable(reason: .invalidPlan))
    #expect(orderOutcome == .safeUnavailable(reason: .invalidPlan))
}
