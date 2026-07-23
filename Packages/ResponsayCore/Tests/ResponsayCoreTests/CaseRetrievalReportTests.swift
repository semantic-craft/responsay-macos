import Testing
import Foundation
@testable import ResponsayCore

/// 246 — 类案检索策略助手（PRD S3）：把"焦点拆解（LLM）+ 分层渠道（#474）"渲染成一份可执行的"检索作战图"
/// Markdown——每条 = 检索式 + 直达链接；顶部带安全降级提示（联网核验前不给判例）。纯渲染、可测。
@Suite struct CaseRetrievalReportTests {
    @Test func rendersFocusWithDeepLinksAndSafetyNote() {
        let plans = CaseRetrievalPlanner.plan(
            CaseFacts(causeOfAction: "买卖合同纠纷", year: "2024", keywords: "免责条款 效力"))
        let md = CaseRetrievalReport.markdown(focus: "免责条款是否有效", plans: plans)
        #expect(md.contains("免责条款是否有效"))                 // 焦点标题
        #expect(md.contains("](https://www.bing.com/search?q=")) // 直达链接（Markdown 形式）
        #expect(md.contains("未") && md.contains("判例"))         // 安全降级提示（联网前不给判例）
    }

    @Test func aggregatesMultipleFocusesUnderOneSafetyNote() {
        let f1 = CaseRetrievalPlanner.plan(CaseFacts(causeOfAction: "买卖合同纠纷", year: "2024", keywords: "免责条款"))
        let f2 = CaseRetrievalPlanner.plan(CaseFacts(keywords: "举证责任 分配"))
        let md = CaseRetrievalReport.markdown(focuses: [("免责条款效力", f1), ("举证责任分配", f2)])
        #expect(md.contains("免责条款效力"))
        #expect(md.contains("举证责任分配"))
        // 安全提示只在顶部出现一次（不是每个焦点都重复）。
        #expect(md.components(separatedBy: CaseRetrievalReport.safetyNote).count == 2)
    }

    @Test func emptyFocusesStillShowsSafetyNote() {
        #expect(CaseRetrievalReport.markdown(focuses: []).contains(CaseRetrievalReport.safetyNote))
    }

    @Test func buildEndToEndFromFocusFacts() {
        // 完整 Core 路径：LLM 给的「焦点(标题+案情字段)」→ 渠道(#474) → 作战图 Markdown。
        let md = CaseRetrievalReport.build(focuses: [
            ("免责条款效力", CaseFacts(causeOfAction: "买卖合同纠纷", year: "2024", keywords: "免责条款")),
            ("举证责任", CaseFacts(keywords: "举证责任 分配")),
        ])
        #expect(md.contains("免责条款效力"))
        #expect(md.contains("举证责任"))
        #expect(md.contains("](https://www.bing.com/search?q="))   // 直达链接
        #expect(md.contains(CaseRetrievalReport.safetyNote))
    }
}
