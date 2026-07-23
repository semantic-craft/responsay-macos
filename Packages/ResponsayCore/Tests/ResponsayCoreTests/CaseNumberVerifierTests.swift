import Testing
@testable import ResponsayCore

/// 473 — 案号验证引擎 = 案例进入展示/报告的唯一准入闸（PRD S1）。纯函数：从文本提取案号 →
/// 格式校验 → 三重分类（+❓疑似虚构）→ 处置。`currentYear` 注入以保持可复现（不用 Date.now）。
@Suite struct CaseNumberVerifierTests {
    private let v = CaseNumberVerifier(currentYear: 2026)

    @Test func extractsCompleteCriminalFirstInstanceCaseNumber() throws {
        let verdict = v.verify("本院认为，依据（2024）皖1702刑初229号判决，应当……")
        #expect(verdict.status == .complete)
        let cn = try #require(verdict.caseNumber)
        #expect(cn.year == 2024)
        #expect(cn.caseType == .criminalFirstInstance)
        #expect(cn.courtCode == "皖1702")
        #expect(cn.sequence == 229)
    }

    @Test func extractsAllStandardZhTypesWithEitherParens() {
        #expect(v.verify("（2024）粤01刑终128号").caseNumber?.caseType == .criminalSecondInstance)
        #expect(v.verify("(2025)粤0305民初2490号").caseNumber?.caseType == .civilFirstInstance)   // 半角
        #expect(v.verify("（2024）京01民终156号").caseNumber?.caseType == .civilSecondInstance)
        #expect(v.verify("（2024）浙0102行初89号").caseNumber?.caseType == .administrativeFirstInstance)
        #expect(v.verify("（2024）苏0508执1024号").caseNumber?.caseType == .execution)
        #expect(v.verify("(2024)苏0508执1024号").status == .complete)                              // 半角
    }

    @Test func extractsCaseLibraryNumber() throws {
        let verdict = v.verify("参见人民法院案例库 入库编号2023-05-1-300-010 一案")
        #expect(verdict.status == .complete)
        let cn = try #require(verdict.caseNumber)
        #expect(cn.caseType == .caseLibrary)
        #expect(cn.year == 2023)
    }

    @Test func plainTextWithoutCaseNumberIsMissing() {
        let verdict = v.verify("本案争议焦点是合同是否成立、执行是否到位。")
        #expect(verdict.status == .missing)
        #expect(verdict.caseNumber == nil)
    }

    @Test func truncatedCaseNumberIsPartial() {
        // 有「代字+类型标记」但缺年份/完整编号（如新闻里只写「皖1702刑初」）→ 部分。
        #expect(v.verify("据皖1702刑初一案的报道……").status == .partial)
        #expect(v.verify("（2024）皖1702刑初").status == .partial)   // 缺 seq号
    }

    @Test func fullShapeWithIllegalYearIsSuspectedFabricated() {
        // 完整形状但年份非法（早于 1900 / 晚于当前年）= 格式不符规范 → ❓疑似虚构（非部分）。
        #expect(v.verify("（1850）皖1702刑初229号").status == .suspectedFabricated)
        #expect(v.verify("（2099）京01民终156号").status == .suspectedFabricated)
    }

    @Test func caseNumberShapedButBogusMarkerIsSuspectedFabricated() {
        // 套了「(YYYY)…号」的壳但类型字编造、不在规范表里 → ❓疑似虚构。
        #expect(v.verify("引用（2024）神仙法院字第999号一案").status == .suspectedFabricated)
    }

    @Test func prefersCompleteOverTruncatedWhenBothPresent() throws {
        let verdict = v.verify("此前皖1702刑初被提及，正式案号为（2024）皖1702刑初229号。")
        #expect(verdict.status == .complete)
        #expect(try #require(verdict.caseNumber).sequence == 229)
    }

    @Test func dispositionFollowsStatus() {
        #expect(v.verify("（2024）皖1702刑初229号").disposition == .admit)                  // complete
        #expect(v.verify("（2024）皖1702刑初").disposition == .attemptCompleteElseDiscard)   // partial
        #expect(v.verify("普通的一段法律分析文字。").disposition == .discard)                  // missing
        #expect(v.verify("（1850）皖1702刑初229号").disposition == .discard)                  // suspect
    }
}
