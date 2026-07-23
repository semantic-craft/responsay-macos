import Testing
import Foundation
@testable import ResponsayCore

/// Records calls and replays a queued list of model outputs.
actor MockLegalExecutor: LegalSkillExecutorAPI {
    private var outputs: [String]
    private(set) var calls: [LegalSkillExecutionRequest] = []
    let runId: String

    init(outputs: [String], runId: String = "run-1") {
        self.outputs = outputs
        self.runId = runId
    }

    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse {
        calls.append(request)
        let output = outputs.isEmpty ? "" : outputs.removeFirst()
        return LegalSkillExecutionResponse(output: output, runId: runId)
    }
}

private func anchorCard(
    skillId: String = "academic.counterargument.cn",
    scene: LegalScene = .academicWriting,
    stage: LegalStage = .argumentDrafting
) -> LegalCandidateCard {
    LegalCandidateCard(id: skillId, skillId: skillId, title: "技能", scene: scene, stage: stage,
                       confidence: 0.9, action: .executeSkill(skillId: skillId))
}

/// 106 — runtime.execute via the executor: success / repair / fallback / guards.
struct LegalSkillExecutorTests {

    @Test func execute_success_returnsDecoded_singleCall() async throws {
        let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "OK")])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        let r = try await runtime.execute(card: anchorCard(), context: ExpressionContext(selectedText: "本文主张…"))
        #expect(r.summary == "OK")
        let calls = await mock.calls
        #expect(calls.count == 1)
        #expect(calls.first?.isRepair == false)
        #expect(calls.first?.purpose == .legalSkill)
    }

    @Test func execute_malformed_thenRepairs() async throws {
        let mock = MockLegalExecutor(outputs: ["{ broken", legalGoodOutputJSON(summary: "修复后")])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        let r = try await runtime.execute(card: anchorCard(), context: ExpressionContext(selectedText: "x"))
        #expect(r.summary == "修复后")
        let calls = await mock.calls
        #expect(calls.count == 2)
        #expect(calls.last?.isRepair == true)
    }

    @Test func execute_repairAlsoFails_fallsBackNeverCrashes() async throws {
        let mock = MockLegalExecutor(outputs: ["{ broken", "{ still broken"])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        let r = try await runtime.execute(card: anchorCard(), context: ExpressionContext(selectedText: "x"))
        if case .fallbackText = r.cards.first {} else { Issue.record("expected fallbackText fallback") }
        #expect(r.insertables.isEmpty)
        let calls = await mock.calls
        #expect(calls.count == 2)
    }

    @Test func execute_forwardsModelRoute() async throws {
        let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        _ = try await runtime.execute(card: anchorCard(), context: ExpressionContext(selectedText: "x"), route: .localOnly)
        let calls = await mock.calls
        #expect(calls.first?.modelRoute == .localOnly)
    }

    @Test func execute_withoutExecutor_throwsNotConfigured() async throws {
        let runtime = try LegalSkillRuntime.bundled()   // no executor
        await #expect(throws: LegalSkillRuntimeError.notConfigured) {
            _ = try await runtime.execute(card: anchorCard(), context: ExpressionContext(selectedText: "x"))
        }
    }

    @Test func execute_genericCard_throwsNotImplemented() async throws {
        let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
        let runtime = try LegalSkillRuntime.bundled(executor: mock)
        let generic = LegalCandidateCard(
            id: "generic.draftParagraph", skillId: "generic.draftParagraph", title: "起草本段",
            scene: .litigation, stage: .briefDrafting, confidence: 0.5,
            action: .executeSkill(skillId: "generic.draftParagraph"))
        await #expect(throws: LegalSkillRuntimeError.executorNotImplemented(skillId: "generic.draftParagraph")) {
            _ = try await runtime.execute(card: generic, context: ExpressionContext(selectedText: "x"))
        }
    }
}
