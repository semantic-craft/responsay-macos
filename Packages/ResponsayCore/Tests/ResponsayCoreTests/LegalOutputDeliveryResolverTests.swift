import Testing
@testable import ResponsayCore

@Suite("475 · 法律输出卡片/上屏双态决策")
struct LegalOutputDeliveryResolverTests {
    private let resolver = LegalOutputDeliveryResolver()

    private func responseWithBody(_ text: String) -> LegalSkillResponse {
        LegalSkillResponse(
            runId: "r", skillId: "s", scene: .litigation, stage: .briefDrafting,
            summary: "",
            cards: [.insertableParagraph(InsertableParagraphCard(
                title: "可插入段落", text: text, containsPendingVerification: false))])
    }

    @Test("默认卡片：偏好为卡片时始终走卡片")
    func cardPreferenceShowsCard() {
        let delivery = resolver.resolve(
            preference: .card, isSecureInput: false, response: responseWithBody("正文"))
        #expect(delivery == .card)
    }

    @Test("上屏：偏好上屏 + 有正文段落 + 非安全输入 → 推送正文")
    func insertPreferencePushesBody() {
        let delivery = resolver.resolve(
            preference: .insert, isSecureInput: false, response: responseWithBody("起诉状正文…"))
        #expect(delivery == .insert(text: "起诉状正文…"))
    }

    @Test("安全输入永不上屏（#052）：偏好上屏但聚焦密码框 → 回退卡片")
    func secureInputNeverInserts() {
        let delivery = resolver.resolve(
            preference: .insert, isSecureInput: true, response: responseWithBody("正文"))
        #expect(delivery == .card)
    }

    @Test("无正文可推：偏好上屏但只有参照卡片 → 回退卡片")
    func insertFallsBackWhenNothingToPush() {
        let referenceOnly = LegalSkillResponse(
            runId: "r", skillId: "s", scene: .litigation, stage: .briefDrafting, summary: "",
            cards: [.counterargument(CounterargumentCard(
                title: "反方观点", thesis: "t", implicitPremises: [], items: []))])
        let delivery = resolver.resolve(
            preference: .insert, isSecureInput: false, response: referenceOnly)
        #expect(delivery == .card)
    }
}
