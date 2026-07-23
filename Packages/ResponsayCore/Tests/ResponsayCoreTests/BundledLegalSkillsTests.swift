import Testing
import Foundation
@testable import ResponsayCore

/// 103 — the bundled v0 legal-skill corpus (10 skills: 2 anchors + 8 stubs)
/// authored under `LegalBrain/LegalSkills/`, compiled via 102, loaded through the
/// SwiftPM resource bundle. Asserts compilation + indexing + anchor completeness.
/// (Schema validity ≠ legal correctness — the builder's correctness sign-off is
/// tracked in the issue's `## Comments`.)
struct BundledLegalSkillsTests {

    private func registry() throws -> LegalSkillRegistry {
        try LegalSkillRegistry.loadBundled()
    }

    @Test func bundleDirectoryResolves() throws {
        #expect(LegalSkillRegistry.bundledSkillsDirectory() != nil)
    }

    @Test func allSkillsCompile() throws {
        // 14 after the two litigation calculator skills were deleted (2026-06-14);
        // 15 after adding style.expression_upgrade.cn (表达升级 backing) on 2026-06-16;
        // 14 again after 案情分析与诉讼策略 was retired and its 多轮对抗 moved to 反方观点;
        // 15 after adding academic.idea_planning.cn (思路推演);
        // 16 after adding academic.prompt_optimization.cn (提示词优化);
        // 17 after adding style.condense.cn (精简压缩, 写作 lane);
        // 11 after the 1.5.0 purge deleted the 6 hidden-but-on-disk overlap skills outright.
        #expect(try registry().skills.count == 11)
    }

    @Test func indexesIntoThreeScenes() throws {
        let reg = try registry()
        let scenes = Set(reg.skills.map(\.metadata.sceneLayer.scene))
        #expect(scenes == [.litigation, .academicWriting, .unknown])
        #expect(reg.candidates(scene: .litigation).count == 1)   // 1.5.0 purge: 引注源验 is the litigation survivor
        #expect(reg.candidates(scene: .academicWriting).count == 5)  // 引注转换/反方观点/思路推演/提示词优化/检索策略
        // 325 slice 3b: the 3 unknown-scene entries are the bundled style.* skills
        // (kind:rewrite) — they belong to the 改写风格 picker, not the ⌥L
        // generation palette, so they no longer surface as generation candidates.
        #expect(reg.candidates(scene: .unknown).count == 0)
    }

    @Test func citationVerifySkillIsBundledAndNamed() throws {
        // 引注源验: the 来源核验 (.verify) selection action runs THIS exact skill id to produce the
        // auto-verify result card. Pin id + title so a rename / typo can't silently break the flow.
        let skill = try #require(try registry().skill(id: "verification.fact_check.cn"))
        #expect(skill.metadata.title == "引注源验")
    }

    @Test func noBundledSkillDeclaresConversation() throws {
        // 划词技能互动: every bundled skill produces a one-shot card. 反方观点's 多轮对抗 is NOT
        // declared here — its card plays the opening round and the 对抗 is entered from the
        // result panel, so tagging it `conversation` would skip the card entirely.
        // `interaction:conversation` stays available for imported third-party skills.
        let conversational = try registry().skills
            .filter { $0.metadata.interaction == .conversation }
            .map(\.id)
        #expect(conversational.isEmpty)
    }

    @Test func candidatesNeverIncludeRewriteKindSkills() throws {
        let reg = try registry()
        for scene in [LegalScene.litigation, .academicWriting, .unknown] {
            #expect(reg.candidates(scene: scene).allSatisfy { $0.metadata.kind != .rewrite })
        }
        // The style.* skills still exist in the raw index (for the rewrite picker),
        // they're just not generation candidates.
        #expect(reg.skills.contains { $0.metadata.kind == .rewrite })
    }

    @Test func everyDomainMatchesSceneLayer() throws {
        // No skill should declare a domain that disagrees with its sceneLayer scene.
        for skill in try registry().skills {
            #expect(skill.metadata.domain == skill.metadata.sceneLayer.scene)
        }
    }

    @Test func anchorsAreFullyStructured() throws {
        let reg = try registry()

        // 1.5.0 curated bundle: the structural anchors are the two load-bearing skills —
        // 引注源验 (backs 来源核验) and 检索策略 (backs 来源辅助检索).
        let a = try #require(reg.skill(id: "verification.fact_check.cn"))
        #expect(a.metadata.outputCards.contains(.verificationTodos))
        #expect(a.reasoningProcedure.contains("提取"))
        #expect(a.outputConstraint.contains("LEGAL_OUTPUT/v1"))

        let b = try #require(reg.skill(id: "research.search_strategy.cn"))
        #expect(b.metadata.outputCards.contains(.strategyRecommendation))
        #expect(b.outputConstraint.contains("LEGAL_OUTPUT/v1"))
    }

    @Test func nonStyleSkillsCarryDisclaimerAndMandatoryMapping() throws {
        for skill in try registry().skills {
            let isStyle = skill.metadata.id.hasPrefix("style.")
            if !isStyle {
                #expect(!skill.metadata.reasoningKernel.mandatoryMapping.isEmpty)
                #expect(!skill.metadata.risk.disclaimer.isEmpty)
            }
            let hasContent = !skill.skillInstructions.isEmpty
                || !skill.reasoningProcedure.isEmpty
                || !skill.outputConstraint.isEmpty
                || !(skill.metadata.prompt?.isEmpty ?? true)
                || !skill.metadata.reasoningKernel.mandatoryMapping.isEmpty
            #expect(hasContent, "skill \(skill.metadata.id) has no instructions/procedure/prompt")
        }
    }

    @Test func routerSurfacesBundledLitigationAnchor() throws {
        // End-to-end: a litigation brief context routes to the bundled anchor A.
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx",
            selectedText: "被告拖欠货款,构成违约。",
            textBeforeCursor: "一、事实与理由\n……"
        )
        let bundle = ContextSignalLayer().assemble(context: ctx, now: Date(timeIntervalSince1970: 0))
        let decision = LegalSceneStageRouter().route(bundle, registry: try registry())
        #expect(decision.tier == "auto")
        #expect(decision.cards.contains { $0.skillId == "verification.fact_check.cn" })
    }
}
