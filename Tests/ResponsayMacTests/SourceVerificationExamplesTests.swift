import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 来源真伪 demo 一致性：新手引导「看演示」里展示的真实引用，必须和程序真实跑出的
/// 检索源 / 深链一致 —— 即用户最关心的「实际跑的效果 = 演示」。素材见 SourceVerificationExamples。
final class SourceVerificationExamplesTests: XCTestCase {
    private let gen = SearchStrategyGenerator()

    private func scholarStrategy(_ query: String) -> SearchStrategy {
        let anchor = VerificationAnchor(id: "s", label: query, kind: .scholarlyArticle,
                                        status: .pending, query: query)
        return gen.strategy(for: anchor, scene: .academicWriting)
    }

    /// 正例（熊伟 / 宋旭光 CLSCI 论文）：真实路由到知网 + 百度学术（学术库可查）。
    func testFindableExamplesRouteToScholarDB() {
        for ex in [SourceVerificationExamples.xiongWeiPaper, SourceVerificationExamples.songXuguangPaper] {
            let sources = scholarStrategy(ex.query).routes.map { $0.source }
            XCTAssertTrue(sources.contains(.cnki), "\(ex.query) 应路由到知网")
            XCTAssertTrue(sources.contains(.baiduScholar), "\(ex.query) 应路由到百度学术")
            XCTAssertTrue(ex.findableInScholarDB)
        }
    }

    /// 兜底（张贤伟新译著）：查询真实产出一条「搜索引擎兜底」百度网页深链。
    func testFallbackExamplesGetSearchEngineRoute() {
        for ex in [SourceVerificationExamples.zhangBookComputable, SourceVerificationExamples.zhangBookIP] {
            let strat = scholarStrategy(ex.query)
            XCTAssertEqual(strat.routes.map { $0.source }, [.cnki, .baiduScholar, .webSearch])
            let url = strat.routes.first { $0.source == .webSearch }?.url?.absoluteString ?? ""
            XCTAssertTrue(url.contains("www.baidu.com/s"), "兜底应为百度网页搜索深链：\(url)")
            XCTAssertTrue(url.contains("wd="))
            XCTAssertFalse(ex.findableInScholarDB)
        }
    }

    /// 演示内容 = 已核实素材：来源核验 demo 的两个锚点分类取自示例数据。
    func testVerifyDemoAnchorsMatchExamples() {
        guard case let .anchors(items) = FeatureDemoScript.verify.resultContent else {
            return XCTFail("verify demo 结果应为 .anchors")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].label.contains("熊伟"))
        XCTAssertEqual(items[0].kind, SourceVerificationExamples.xiongWeiPaper.kindLabel)
        XCTAssertTrue(items[0].sourceTitle.contains("现代法学"))
        XCTAssertTrue(items[0].evidence.contains("100–114"))
        XCTAssertEqual(items[0].searchQuery, SourceVerificationExamples.xiongWeiPaper.query)
        XCTAssertTrue(items[0].matchFields.contains("题名一致"))
        XCTAssertTrue(items[0].matchFields.contains("作者：熊伟"))
        XCTAssertTrue(items[1].label.contains("宋旭光"))
        XCTAssertEqual(items[1].kind, SourceVerificationExamples.songXuguangPaper.kindLabel)
        XCTAssertTrue(items[1].sourceTitle.contains("比较法研究"))
        XCTAssertTrue(items[1].evidence.contains("2020"))
        XCTAssertEqual(items[1].searchQuery, SourceVerificationExamples.songXuguangPaper.query)
        XCTAssertTrue(items[1].matchFields.contains("题名一致"))
        XCTAssertTrue(items[1].matchFields.contains("作者：宋旭光"))
    }

    /// 演示 = 已核实素材 + 真实链路：兜底 demo 搜的就是示例 query，结果卡指向已核实来源。
    func testFallbackDemoSearchesExampleQuery_andLinksVerifiedSource() {
        guard case let .webSearchHost(_, query) = FeatureDemoScript.fallback.host else {
            return XCTFail("fallback demo host 应为 .webSearchHost")
        }
        XCTAssertEqual(query, SourceVerificationExamples.fallbackPrimary.query)
        // 该 query 真实跑出的兜底链确实是百度网页搜索：
        let hasBaiduWeb = scholarStrategy(query).routes.contains {
            $0.source == .webSearch && ($0.url?.absoluteString.contains("www.baidu.com/s") ?? false)
        }
        XCTAssertTrue(hasBaiduWeb)
        // 演示结果卡指向已联网核实的来源（豆瓣 37422136 / 商务印书馆 cp.com.cn）：
        guard case let .webResults(items) = FeatureDemoScript.fallback.resultContent else {
            return XCTFail("fallback demo 结果应为 .webResults")
        }
        XCTAssertTrue(items.contains {
            $0.url.contains("douban.com/subject/37422136") || $0.url.contains("cp.com.cn")
        })
    }
}
