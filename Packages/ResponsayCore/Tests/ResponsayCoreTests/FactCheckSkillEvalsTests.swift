import Testing
import Foundation
@testable import ResponsayCore

/// E2E Evaluation for the `verification.fact_check.cn` skill.
/// Run this with a valid API key to test the model's instruction following rate.
/// Example: `DEEPSEEK_API_KEY="sk-..." swift test --filter FactCheckSkillEvalsTests`
@Suite("Fact Check Mega-Skill Evaluations")
struct FactCheckSkillEvalsTests {

    struct TestCase {
        let id: String
        let desc: String
        let selectedText: String
        let textBeforeCursor: String
        let expectedAnchorCount: Int
        let expectedFirstKind: String
    }

    let dataset = [
        TestCase(
            id: "tc001", desc: "真法条提取",
            selectedText: "根据《中华人民共和国民法典》第一千零二十四条规定，民事主体享有名誉权。任何组织或者个人不得以侮辱、诽谤等方式侵害他人的名誉权。",
            textBeforeCursor: "一、事实与理由\n",
            expectedAnchorCount: 1, expectedFirstKind: "law"
        ),
        TestCase(
            id: "tc002", desc: "假法条（捏造法条）提取",
            selectedText: "根据《中华人民共和国民法典》第一千零二十四条之一的规定，侵犯虚拟形象权利的，应当承担三倍赔偿责任。",
            textBeforeCursor: "一、事实与理由\n",
            expectedAnchorCount: 1, expectedFirstKind: "law"
        ),
        TestCase(
            id: "tc003", desc: "真实指导性案例案号",
            selectedText: "正如指导案例24号（荣宝斋诉荣宝斋（徐州）艺术品有限公司侵害商标权及不正当竞争纠纷案）所确立的裁判要旨...",
            textBeforeCursor: "二、裁判依据分析\n",
            expectedAnchorCount: 1, expectedFirstKind: "caseLaw"
        ),
        TestCase(
            id: "tc004", desc: "伪造最高院案号",
            selectedText: "参考最高人民法院作出的(2023)最高法民终8888号判决书，法院认为比特币不具有任何财产属性，不能作为执行标的。",
            textBeforeCursor: "二、裁判依据分析\n",
            expectedAnchorCount: 1, expectedFirstKind: "caseLaw"
        ),
        // 335: 文献提取两例（原 tc005/tc006，expectedFirstKind=scholarlyArticle）已移出本 eval。
        // 学术文献核查归 `verification.literature_search.cn`（scene: academicWriting），不是
        // `verification.fact_check.cn`（litigation, law/case）。如需文献 eval，另建独立套件。
        TestCase(
            id: "tc007", desc: "案件事实描述（无案号）",
            selectedText: "我们公司之前有个员工竞业限制没给补偿金，法院判我们输了，因为我们长达六个月没有支付补偿金，员工主张竞业限制协议解除。",
            textBeforeCursor: "四、类案检索需求\n",
            expectedAnchorCount: 1, expectedFirstKind: "caseLaw"
        )
    ]

    /// Live E2E eval — **opt-in only**. Gated behind `RUN_LIVE_EVALS=1` (issue 334) so a plain
    /// `swift test` never hits the network just because a `DEEPSEEK_API_KEY` happens to be loaded
    /// in the shell. Run it explicitly:
    ///   `RUN_LIVE_EVALS=1 DEEPSEEK_API_KEY="sk-..." swift test --filter FactCheckSkillEvalsTests`
    @Test(
        "Evaluate Fact Check Prompt against Real LLM",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LIVE_EVALS"] == "1"))
    func evaluatePrompt() async throws {
        let apiKey = try #require(
            ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
            "RUN_LIVE_EVALS=1 requires DEEPSEEK_API_KEY to be set.")

        let endpoint = LLMEndpoint(
            providerId: "deepseek",
            baseURL: "https://api.deepseek.com/v1/chat/completions",
            model: "deepseek-chat",
            apiKey: apiKey,
            thinkingEnabled: false
        )
        let executor = DirectLegalSkillExecutorAPI(endpoint: endpoint)

        let runtime = try LegalSkillRuntime.bundled(executor: executor)
        let validator = LegalOutputValidator()

        var passed = 0
        var failed = 0

        for tc in dataset {
            // 335: fetch the skill directly by id, NOT via route(). The router classifies scene
            // from app/heading signals (not the selectedText's content), so it gated these
            // litigation source-checking cases out before the LLM extraction could be exercised —
            // that mismatch was the real cause of the reported tc003–tc007 "failures", not model
            // drift. Routing coverage lives in `factCheckRouteSuggestedForLawContexts`; this eval
            // measures the skill's extraction quality.
            guard let skill = runtime.registry.skill(id: "verification.fact_check.cn") else {
                print("❌ \(tc.id): Skill not found in registry")
                failed += 1
                continue
            }
            let payload = LegalContextPayload(
                selectedText: tc.selectedText,
                nearbyHeading: nil,
                scene: .litigation,
                stage: .briefDrafting,
                appName: "Evaluation",
                contextScope: .selectedTextOnly
            )
            let profile = LegalPracticeProfile(id: "p", role: .practitioner, modelPreference: .cloudFirst, createdAt: "", updatedAt: "")
            let assembler = LegalPromptAssembler()
            let prompt = assembler.assemble(skill: skill, context: payload, profile: profile)
            let request = LegalSkillExecutionRequest(
                skillId: skill.metadata.id,
                systemPrompt: prompt.system,
                userPrompt: prompt.user,
                modelRoute: .cloudAllowed
            )

            print("▶️ Running \(tc.id) - \(tc.desc)...")
            do {
                let executionResponse = try await executor.executeSkill(request)

                // Validate through the real LEGAL_OUTPUT/v1 pipeline
                let envelope = LegalOutputValidator.Envelope(
                    runId: "eval-\(tc.id)",
                    skillId: "verification.fact_check.cn",
                    scene: .litigation,
                    stage: .briefDrafting
                )
                let response = await validator.validate(
                    rawOutput: executionResponse.output,
                    envelope: envelope,
                    repair: { brokenOutput in
                        let repairPrompt = assembler.repairPrompt(brokenOutput: brokenOutput)
                        let repairRequest = LegalSkillExecutionRequest(
                            skillId: "verification.fact_check.cn",
                            systemPrompt: repairPrompt.system,
                            userPrompt: repairPrompt.user,
                            modelRoute: .cloudAllowed
                        )
                        return try await executor.executeSkill(repairRequest).output
                    }
                )

                // Check it didn't fall back to plain text
                let isFallback = response.cards.contains { card in
                    if case .fallbackText = card { return true }
                    return false
                }
                if isFallback {
                    print("❌ \(tc.id): Output fell back to plain text — model did not produce LEGAL_OUTPUT/v1")
                    failed += 1
                    continue
                }

                // Check verificationAnchors count
                if response.verificationAnchors.count != tc.expectedAnchorCount {
                    print("❌ \(tc.id): Expected \(tc.expectedAnchorCount) anchors, got \(response.verificationAnchors.count).")
                    failed += 1
                    continue
                }

                // Check first anchor kind
                if let first = response.verificationAnchors.first {
                    let kind = first.kind.rawValue
                    if kind != tc.expectedFirstKind {
                        print("❌ \(tc.id): Expected kind '\(tc.expectedFirstKind)', got '\(kind)'.")
                        failed += 1
                        continue
                    }
                }

                print("✅ \(tc.id) Passed!")
                passed += 1

            } catch {
                print("❌ \(tc.id): Execution failed with error: \(error)")
                failed += 1
            }
        }

        print("\n=== Eval Results ===")
        print("Passed: \(passed)")
        print("Failed: \(failed)")
        print("Total: \(dataset.count)")

        #expect(failed == 0, "All evaluation cases must pass.")
    }

    /// Deterministic regression net for the **routing** half (no network): for 法条 (law)
    /// contexts the route suggests `verification.fact_check.cn`.
    ///
    /// Resolution note (issue 335): routing classifies scene from app/heading signals, NOT from
    /// the selectedText's content — so caseLaw (案号) contexts with the eval's synthetic headings
    /// do not surface fact-check, which is exactly why the externally-reported "tc003–tc007
    /// failures" happened (the route gate, not model drift). The fix was to decouple the eval
    /// from routing (it now fetches the skill by id and tests extraction); this test keeps the
    /// law-context routing pinned as a regression net. Asserting only the law cases is deliberate
    /// — the app/heading-driven classification for other headings is not what this eval measures.
    @Test("Fact-check route is suggested for 法条 (law) contexts (deterministic, no network)")
    func factCheckRouteSuggestedForLawContexts() throws {
        let now = Date(timeIntervalSince1970: 0)
        let runtime = try LegalSkillRuntime.bundled(executor: nil)
        let lawCases = dataset.filter { $0.expectedFirstKind == "law" }
        #expect(!lawCases.isEmpty, "dataset should contain at least one 法条 case")
        for tc in lawCases {
            let ctx = ExpressionContext(
                appName: "Evaluation",
                bundleIdentifier: "com.responsay.eval",
                windowTitle: "起诉状.docx",
                selectedText: tc.selectedText,
                textBeforeCursor: tc.textBeforeCursor)
            let outcome = runtime.route(context: ctx, now: now)
            #expect(
                outcome.cards.contains { $0.skillId == "verification.fact_check.cn" },
                "\(tc.id) (\(tc.desc)): route did not suggest verification.fact_check.cn")
        }
    }
}
