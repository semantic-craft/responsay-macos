import Testing
@testable import ResponsayCore

/// 「继续对抗」交给多轮框的上下文。stance 指令都说「针对上面的论证 / 上面的方案」，所以那个东西
/// 必须真的在上下文里，否则首轮加压会对着空气开火。
@Suite struct DebateSeedTests {

    private func response(
        skillId: String = "academic.idea_planning.cn",
        summary: String,
        insertables: [InsertableLegalText] = []
    ) -> LegalSkillResponse {
        LegalSkillResponse(
            runId: "r1", skillId: skillId, scene: .academicWriting, stage: .argumentDrafting,
            summary: summary, cards: [], insertables: insertables, verificationAnchors: [], warnings: [])
    }

    private func insertable(_ text: String) -> InsertableLegalText {
        InsertableLegalText(id: "i1", title: "方案陈述", text: text,
                            insertPolicy: .noInsert, containsPendingVerification: false)
    }

    @Test func summaryAloneBecomesTheSubject() {
        let seed = DebateSeed.subject(from: response(summary: "本方案主张先做窄版本。"))
        #expect(seed == "本方案主张先做窄版本。")
    }

    /// 卡片里可插入的正文也要带上——对抗要针对用户刚读到的那份分析，不是只针对一句摘要。
    @Test func insertableProseIsCarriedAlongsideTheSummary() {
        let seed = DebateSeed.subject(from: response(
            summary: "摘要句。", insertables: [insertable("在做什么：先做窄版本。不做：多端同步。")]))
        #expect(seed.contains("摘要句。"))
        #expect(seed.contains("不做：多端同步。"))
    }

    @Test func blankPartsAreDropped() {
        let seed = DebateSeed.subject(from: response(
            summary: "   ", insertables: [insertable("  "), insertable("真正的内容")]))
        #expect(seed == "真正的内容")
    }

    @Test func emptyResponseYieldsEmptySubject() {
        #expect(DebateSeed.subject(from: response(summary: "")).isEmpty)
    }
}
