import Testing
import Foundation
@testable import ResponsayCore

/// 108 — FactCoordinateExtractor: each kind → a pending [待核] anchor.
struct FactCoordinateExtractorTests {
    private let extractor = FactCoordinateExtractor()

    private func first(_ text: String) -> VerificationAnchor? { extractor.extract(from: text).first }

    @Test func law_withSpaces_parsesToLawPending() {
        // Acceptance: "《个保法》第 24 条" → VerificationKind.law, pending.
        let a = first("依据《个保法》第 24 条，处理者应当……")
        #expect(a?.kind == .law)
        #expect(a?.status == .pending)
        #expect(a?.label == "《个保法》第24条")        // internal spaces collapsed
    }

    @Test func law_arabicAndChineseNumerals() {
        #expect(first("《民法典》第577条")?.label == "《民法典》第577条")
        #expect(first("《民法典》第五百七十七条")?.kind == .law)
    }

    @Test func caseNumber_parsesToCaseLaw() {
        let a = first("参见（2021）京01民终1234号判决")
        #expect(a?.kind == .caseLaw)
        #expect(a?.label.contains("号") == true)
    }

    @Test func standard_parsesToStandard() {
        let a = first("符合 GB/T 39335-2020 的要求")
        #expect(a?.kind == .standard)
        #expect(a?.label.contains("39335") == true)
    }

    @Test func date_parsesToDate() {
        #expect(extractor.extract(from: "于2021年1月1日生效").contains { $0.kind == .date })
        #expect(extractor.extract(from: "签订日期 2020-06-30").contains { $0.kind == .date })
    }

    @Test func money_parsesToMoney() {
        #expect(extractor.extract(from: "标的额 120万元").contains { $0.kind == .money && $0.label.contains("万元") })
    }

    @Test func deduplicatesByLabel() {
        let anchors = extractor.extract(from: "《个保法》第24条……再次提到《个保法》第24条")
        #expect(anchors.filter { $0.label == "《个保法》第24条" }.count == 1)
    }

    @Test func emptyText_yieldsNoAnchors() {
        #expect(extractor.extract(from: "这段话没有任何法律坐标。").isEmpty)
    }

    // 189 — 规范性文件号 (六角括号) is now extracted, distinct from 案号 (圆括号).
    @Test func documentNumber_hexagonBracket_parsesToOfficialDocument() {
        let a = first("依据国发〔2007〕19号文件……")
        #expect(a?.kind == .officialDocument)
        #expect(a?.label == "国发〔2007〕19号")
    }

    @Test func docNumber_distinctFromCaseNumber() {
        #expect(first("见法释〔2018〕1号")?.kind == .officialDocument)   // 六角 → 文件号
        #expect(first("见（2018）京01民终1号")?.kind == .caseLaw)        // 圆括号 → 案号
    }

    // 189 — law rule now captures 款 and 项 (and a revision year).
    @Test func law_capturesClauseAndItem() {
        #expect(first("适用《民法总则》第27条第2款第3项的规定")?.label == "《民法总则》第27条第2款第3项")
        #expect(first("依《公司法》（2013年修正）第36条")?.label == "《公司法》（2013年修正）第36条")
    }
}
