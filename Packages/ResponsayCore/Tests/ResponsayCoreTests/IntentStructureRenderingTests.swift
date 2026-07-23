import Foundation
import Testing
@testable import ResponsayCore

// #563 — organizing out-of-order thoughts: the plan may only ARRANGE verified renderable units
// (paragraphs / bullets / numbered steps / foregrounding); the deterministic renderer alone
// produces the formatting. Conservation is the hard boundary — every renderable atom exactly
// once — and prose stays prose unless the speech clearly calls for structure.

private func compileStructured(
    _ transcript: String,
    plan: @escaping @Sendable ([IntentSourceUnit]) -> IntentPlan
) async -> IntentCompilationOutcome {
    let compiler = FixtureIntentCompiler { input in
        try JSONEncoder().encode(plan(input.sourceUnits))
    }
    return await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: transcript,
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)
}

private func renderPlan(
    _ decision: IntentPlanDecision = .render,
    roles: [IntentSourceRole],
    structure: IntentPlanStructure?
) -> @Sendable ([IntentSourceUnit]) -> IntentPlan {
    { sources in
        IntentPlan(
            version: 1,
            decision: decision,
            units: zip(sources, roles).map { .init(source: .init($0), role: $1) },
            supersessions: [],
            structure: structure)
    }
}

@Test func structure_bulletList_zh_formattingInstructionExcluded() async {
    let outcome = await compileStructured("帮我分三点写，备份数据，通知客户，更新文档",
        plan: renderPlan(
            roles: [.sideNote, .content, .content, .content],
            structure: IntentPlanStructure(
                kind: .bulletList,
                groups: [["source-0001"], ["source-0002"], ["source-0003"]])))

    #expect(outcome == .insertable(text: "- 备份数据\n- 通知客户\n- 更新文档", route: .intentPlan))
}

@Test func structure_numberedSteps_mixedLanguage() async {
    let outcome = await compileStructured("发 release notes 前，先 tag 版本，再跑 CI，最后发 TestFlight",
        plan: renderPlan(
            roles: [.sideNote, .content, .content, .content],
            structure: IntentPlanStructure(
                kind: .numberedSteps,
                groups: [["source-0001"], ["source-0002"], ["source-0003"]])))

    #expect(outcome == .insertable(
        text: "1. 先 tag 版本\n2. 再跑 CI\n3. 最后发 TestFlight", route: .intentPlan))
}

@Test func structure_paragraphs_foregroundExplicitKeyDecision() async {
    // Background first, key decision last — the user flags what matters; paragraphs foreground
    // it without adding a single word (conservation: all three units still present).
    let outcome = await compileStructured("预算还没批，人手也不够，最重要的是周四必须交稿。",
        plan: renderPlan(
            roles: [.content, .content, .content],
            structure: IntentPlanStructure(
                kind: .paragraphs,
                groups: [["source-0002"], ["source-0000", "source-0001"]])))

    #expect(outcome == .insertable(
        text: "最重要的是周四必须交稿。\n\n预算还没批，人手也不够", route: .intentPlan))
}

@Test func structure_bulletList_english_trimsClauseCommasOnly() async {
    let outcome = await compileStructured(
        "Three things before Friday, ship the beta, email the vendor, book the demo room",
        plan: renderPlan(
            roles: [.sideNote, .content, .content, .content],
            structure: IntentPlanStructure(
                kind: .bulletList,
                groups: [["source-0001"], ["source-0002"], ["source-0003"]])))

    #expect(outcome == .insertable(
        text: "- ship the beta\n- email the vendor\n- book the demo room", route: .intentPlan))
}

@Test func structure_protectedLiteralsSurviveRestructuring() async {
    // NOTE: dotted literals (emails/URLs) get split by the sentence segmenter — the paired
    // property tests for those belong to the #567 conformance corpus. Here: amount + 编号.
    let outcome = await compileStructured("先付 3000 元定金，再把合同编号 HT-2026-071 发给对方",
        plan: renderPlan(
            roles: [.content, .content],
            structure: IntentPlanStructure(
                kind: .numberedSteps,
                groups: [["source-0000"], ["source-0001"]])))

    guard case let .insertable(text, _) = outcome else {
        Issue.record("expected insertable, got \(outcome)")
        return
    }
    #expect(text.contains("3000"))
    #expect(text.contains("HT-2026-071"))
    #expect(text == "1. 先付 3000 元定金\n2. 再把合同编号 HT-2026-071 发给对方")
}

@Test func structure_conservationViolations_areRejectedNotInserted() async {
    let transcript = "第一件事，第二件事，第三件事"
    let cases: [(String, IntentPlanStructure)] = [
        ("duplicated unit", .init(kind: .bulletList,
            groups: [["source-0000"], ["source-0001", "source-0000"]])),
        ("dropped unit", .init(kind: .bulletList,
            groups: [["source-0000"], ["source-0001"]])),
        ("unknown unit", .init(kind: .bulletList,
            groups: [["source-0000"], ["source-0001"], ["source-9999"]])),
        ("single group REORDERED — normalization may not change meaning", .init(kind: .bulletList,
            groups: [["source-0002", "source-0000", "source-0001"]])),
        ("empty group", .init(kind: .bulletList,
            groups: [["source-0000"], ["source-0001", "source-0002"], []]))
    ]
    for (name, structure) in cases {
        let outcome = await compileStructured(transcript,
            plan: renderPlan(roles: [.content, .content, .content], structure: structure))
        #expect(outcome == .safeUnavailable(reason: .invalidPlan), "\(name)")
    }

    // #575 amendment to spec decision 17: ONE in-order full-coverage group is prose in a
    // costume that weak models put on stochastically — the verifier now strips it instead of
    // discarding the plan. The rendered text must be EXACTLY the prose rendering (no bullets).
    let costume = await compileStructured(transcript,
        plan: renderPlan(roles: [.content, .content, .content],
            structure: IntentPlanStructure(
                kind: .bulletList,
                groups: [["source-0000", "source-0001", "source-0002"]])))
    guard case let .insertable(text, _) = costume else {
        Issue.record("expected normalized-to-prose insertable, got \(costume)")
        return
    }
    #expect(!text.contains("-"))
    #expect(text == "第一件事，第二件事，第三件事")

    // Structure may not smuggle a non-renderable unit (side note) back into the output.
    let noteLeak = await compileStructured("备份数据，这句不用写，通知客户",
        plan: renderPlan(
            roles: [.content, .sideNote, .content],
            structure: IntentPlanStructure(
                kind: .bulletList,
                groups: [["source-0000"], ["source-0001"], ["source-0002"]])))
    #expect(noteLeak == .safeUnavailable(reason: .invalidPlan))
}

@Test func structure_ordinaryProseStaysProse_noOverFormatting() async {
    // noIntentControl may not carry structure at all — the explicit ordinary route stays 逐字.
    let transcript = "今天的评审整体顺利，大家对方案没有原则性意见"
    let structured = await compileStructured(transcript,
        plan: renderPlan(.noIntentControl, roles: [.content, .content],
            structure: IntentPlanStructure(
                kind: .bulletList, groups: [["source-0000"], ["source-0001"]])))
    #expect(structured == .safeUnavailable(reason: .invalidPlan))

    let prose = await compileStructured(transcript,
        plan: renderPlan(.noIntentControl, roles: [.content, .content], structure: nil))
    #expect(prose == .insertable(text: transcript, route: .ordinaryPolished))
}

@Test func structure_strictDecoding_rejectsUnknownFieldsAndDefaultsToProse() throws {
    let good = #"{"kind":"bulletList","groups":[["source-0000"],["source-0001"]]}"#
    let decoded = try JSONDecoder().decode(IntentPlanStructure.self, from: Data(good.utf8))
    #expect(decoded == IntentPlanStructure(
        kind: .bulletList, groups: [["source-0000"], ["source-0001"]]))

    let unknownField = #"{"kind":"bulletList","groups":[["source-0000"]],"title":"总结"}"#
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(IntentPlanStructure.self, from: Data(unknownField.utf8))
    }

    let planWithout = #"{"version":1,"decision":"render","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#
    #expect(try JSONDecoder().decode(IntentPlan.self, from: Data(planWithout.utf8)).structure == nil)
}
