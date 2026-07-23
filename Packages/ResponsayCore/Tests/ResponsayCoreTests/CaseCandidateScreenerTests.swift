import Testing
@testable import ResponsayCore

@Suite("488 · 找类案联网候选筛选（案号闸 + 交叉验证 + 两高配额）")
struct CaseCandidateScreenerTests {
    private let screener = CaseCandidateScreener(currentYear: 2026)

    // 两个独立 host → 交叉验证通过
    private let twoSources: @Sendable (String) async -> [String] = { _ in
        ["https://wenshu.court.gov.cn/a", "https://news.qq.com/b"]
    }

    @Test("有效案号 + 交叉验证命中独立来源 → ✅verified")
    func validCaseWithSourcesIsVerified() async {
        let c = CaseCandidate(
            title: "竞业限制违约金案",
            text: "（2023）沪0115民初1234号，法院认为……",
            sourceURLs: ["https://wenshu.court.gov.cn/a"], isTypicalCase: false)
        let out = await screener.screen([c], crossCheck: twoSources)
        #expect(out.count == 1)
        #expect(out.first?.label == .verified)
    }

    @Test("无案号候选 → 废弃，不出现在展示列表")
    func numberlessCandidateDropped() async {
        let c = CaseCandidate(
            title: "某劳动争议案", text: "法院支持了劳动者的主张，公司败诉。",
            sourceURLs: ["https://example.com/x"], isTypicalCase: false)
        let out = await screener.screen([c], crossCheck: twoSources)
        #expect(out.isEmpty)
    }

    @Test("有效案号但交叉验证零独立来源 → ⚠️AI 生成·未核验")
    func validCaseWithoutSourcesIsUnverified() async {
        let c = CaseCandidate(
            title: "买卖合同案", text: "（2022）粤01民终5678号",
            sourceURLs: [], isTypicalCase: false)
        let out = await screener.screen([c], crossCheck: { _ in [] })
        #expect(out.count == 1)
        #expect(out.first?.label == .aiUnverified)
    }

    private func regular(_ n: String) -> CaseCandidate {
        CaseCandidate(title: "类案\(n)", text: n, sourceURLs: ["https://wenshu.court.gov.cn/\(n)"], isTypicalCase: false)
    }
    private let threeRegulars = ["（2023）沪0115民初1234号", "（2022）粤01民终5678号", "（2021）京0105民初9999号"]

    @Test("两高典型案例免案号闸：有足够普通类案时入选并标⚠️未核验")
    func typicalCaseExemptAndLabeledUnverified() async {
        let typical = CaseCandidate(
            title: "最高法典型案例", text: "最高人民法院发布的典型案例，无文书案号。",
            sourceURLs: ["https://www.court.gov.cn/typical/1"], isTypicalCase: true)
        let candidates = threeRegulars.map(regular) + [typical]
        let out = await screener.screen(candidates, crossCheck: twoSources)
        #expect(out.count == 4)
        let typicalOut = out.first { $0.candidate.isTypicalCase }
        #expect(typicalOut?.label == .aiUnverified)
    }

    private func typical(_ n: String) -> CaseCandidate {
        CaseCandidate(title: "典型\(n)", text: "典型案例\(n)", sourceURLs: ["https://www.court.gov.cn/\(n)"], isTypicalCase: true)
    }

    @Test("两高占比 ≤30%：3 普通 + 3 典型 → 仅保留 1 个典型")
    func typicalCasesCappedAtThirtyPercent() async {
        let candidates = threeRegulars.map(regular) + ["a", "b", "c"].map(typical)
        let out = await screener.screen(candidates, crossCheck: twoSources)
        #expect(out.filter { $0.candidate.isTypicalCase }.count == 1)
        #expect(out.count == 4)
    }

    @Test("不能全靠两高：无普通类案 → 典型案例全部不收")
    func noTypicalsWithoutRegulars() async {
        let out = await screener.screen(["a", "b"].map(typical), crossCheck: twoSources)
        #expect(out.isEmpty)
    }
}
