import Testing
import Foundation
@testable import ResponsayCore

/// 108 — VerificationPostProcessor: backfill missing anchors + keep [待核] on inserts.
struct VerificationPostProcessTests {
    private let processor = VerificationPostProcessor()
    private let launcher = VerificationSearchLauncher()

    private func response(summary: String, cards: [LegalOutputCard] = [], anchors: [VerificationAnchor] = []) -> LegalSkillResponse {
        LegalSkillResponse(runId: "r", skillId: "s", scene: .privacy, stage: .piaTriage,
                           summary: summary, cards: cards, verificationAnchors: anchors)
    }

    @Test func backfill_addsAnchorForUnanchoredLaw() {
        // Acceptance: model asserts a 法条 with NO anchor → one gets added in post-processing.
        let r = response(summary: "处理者应依据《个保法》第24条履行义务。")
        let out = processor.backfill(r)
        #expect(out.verificationAnchors.contains { $0.label == "《个保法》第24条" && $0.status == .pending })
    }

    @Test func backfill_doesNotDuplicateAlreadyAnchored() {
        let existing = VerificationAnchor(id: "x", label: "《个保法》第24条", kind: .law, query: "q")
        let r = response(summary: "见《个保法》第24条。", anchors: [existing])
        let out = processor.backfill(r)
        #expect(out.verificationAnchors.filter { $0.label == "《个保法》第24条" }.count == 1)
    }

    @Test func backfill_scansInsertableParagraphText() {
        let r = response(summary: "", cards: [
            .insertableParagraph(InsertableParagraphCard(
                title: "段落", text: "本案标的额 120万元，应于2021年1月1日前支付。",
                containsPendingVerification: false)),
        ])
        let kinds = Set(processor.backfill(r).verificationAnchors.map(\.kind))
        #expect(kinds.contains(.money))
        #expect(kinds.contains(.date))
    }

    @Test func ensureTags_keepsPendingTagOnInsertedText() {
        // Acceptance: inserted body keeps [待核].
        let tagged = processor.ensureTags(in: "依据《民法典》第577条，被告应承担违约责任。")
        #expect(tagged.contains("《民法典》第577条[待核]"))
    }

    @Test func ensureTags_isIdempotent() {
        let once = processor.ensureTags(in: "见《民法典》第577条。")
        let twice = processor.ensureTags(in: once)
        #expect(once == twice)
        #expect(twice.components(separatedBy: "[待核]").count == 2)   // exactly one tag
    }

    // 猎虫④ F1 — 条 vs 条之一 同段并引（刑法危险驾驶/交通肇事的真实高频写法）：
    // 旧 replacingOccurrences 把短 label 打穿长坐标，输出
    // 「《刑法》第133条[待核]之一」——插入正文被实质篡改。
    @Test func ensureTags_doesNotStampThroughLongerCoordinate() {
        let text = "依《刑法》第133条处罚；情节恶劣的，依《刑法》第133条之一处罚。"
        let out = processor.ensureTags(in: text)
        #expect(out.contains("《刑法》第133条[待核]处罚"))
        #expect(out.contains("《刑法》第133条之一[待核]处罚"))
        #expect(!out.contains("第133条[待核]之一"))
    }

    // 猎虫④ F2 — 同一坐标出现两次、其一已带标：旧 contains(tagged) 把
    // 「某处已标」当「处处已标」，第二处原样落宿主。
    @Test func ensureTags_tagsEveryOccurrenceNotJustFirst() {
        let text = "前引《民法典》第577条[待核]；本案仍适用《民法典》第577条。"
        let out = processor.ensureTags(in: text)
        #expect(out.components(separatedBy: "《民法典》第577条[待核]").count == 3)   // both tagged
        #expect(!out.contains("[待核][待核]"))   // the pre-tagged one untouched
    }

    // 修复 verifier 抓出的残留：长坐标已核(settled)、短前缀坐标仍 pending 时，
    // settled 长 label 必须继续充当遮蔽区间——否则 F1 的篡改经豁免路径还魂。
    @Test func ensureTags_settledLongLabelStillShieldsPendingPrefix() {
        let text = "依《刑法》第133条之一处罚；另见《刑法》第133条。"
        let settled = VerificationAnchor(
            id: "s", label: "《刑法》第133条之一", kind: .law, status: .verifiedLaw,
            query: "《刑法》第133条之一")
        let out = processor.ensureTags(in: text, anchors: [settled])
        #expect(!out.contains("第133条[待核]之一"))            // settled 区间不被打穿
        #expect(out.contains("另见《刑法》第133条[待核]。"))     // 独立的 pending 出现照常打标
    }

    @Test func launcher_buildsWorkingBaiduScholarDeepLink() {
        // Acceptance: a pending anchor → a working baidu-scholar deep-link (no "verified" claim).
        let anchor = VerificationAnchor(id: "a", label: "个人信息保护影响评估", kind: .scholarlyArticle,
                                        query: "个人信息保护影响评估")
        let url = launcher.baiduScholarURL(for: anchor)
        #expect(url?.host == "xueshu.baidu.com")
        #expect(url?.query?.contains("wd=") == true)
        #expect(launcher.primaryURL(for: anchor)?.host == "xueshu.baidu.com")
        // law → general web search (no paywalled DB claim)
        let law = VerificationAnchor(id: "l", label: "《个保法》第24条", kind: .law, query: "《个保法》第24条")
        #expect(launcher.primaryURL(for: law)?.host == "www.baidu.com")
    }
}
