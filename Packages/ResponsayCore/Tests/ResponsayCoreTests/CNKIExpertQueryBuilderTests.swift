import Testing
import Foundation
@testable import ResponsayCore

// MARK: - CNKI 专业检索式构造器（契约移植自 opencli-stack buildCnkiProfessionalExpr）

struct CNKIExpertQueryBuilderTests {

    @Test func bareQuery_buildsSubjectRelatedMatch() {
        #expect(CNKIExpertQueryBuilder.build(query: "人工智能") == "SU %= '人工智能'")
    }

    @Test func multiWordSubject_joinsWithStar() {
        // 同字段多词用「 * 」组合，单个 SU %= 前缀（非 SU=('a') AND SU=('b')）。
        #expect(CNKIExpertQueryBuilder.build(query: "数字 法治") == "SU %= '数字' * '法治'")
    }

    @Test func withAuthor_routesToAU() {
        let expr = CNKIExpertQueryBuilder.build(.init(query: "人工智能", author: "张三"))
        #expect(expr == "SU %= '人工智能' AND AU = '张三'")
    }

    @Test func withJournal_routesToLY() {
        let expr = CNKIExpertQueryBuilder.build(.init(query: "人工智能", journal: "法学研究"))
        #expect(expr == "SU %= '人工智能' AND LY = '法学研究'")
    }

    @Test func withMultipleJournals_ORsThem() {
        let expr = CNKIExpertQueryBuilder.build(.init(query: "人工智能", journal: "法学研究+中国法学"))
        #expect(expr == "SU %= '人工智能' AND (LY = '法学研究' OR LY = '中国法学')")
    }

    @Test func withAuthorAndJournal_ANDsAll() {
        let expr = CNKIExpertQueryBuilder.build(.init(query: "人工智能", author: "张三", journal: "法学研究"))
        #expect(expr == "SU %= '人工智能' AND AU = '张三' AND LY = '法学研究'")
    }

    @Test func titleField_usesPercentNotPercentEquals() {
        let expr = CNKIExpertQueryBuilder.build(.init(query: "人工智能", field: "TI"))
        #expect(expr == "TI % '人工智能'")
    }

    @Test func apostrophe_isEscapedNotStripped() {
        // 词内单引号转义为 ''（保住 '...' 引号配对），不再像旧实现那样直接删掉。
        #expect(CNKIExpertQueryBuilder.build(query: "Law's Empire") == "SU %= 'Law''s' * 'Empire'")
    }

    @Test func unknownField_fallsBackToSubject() {
        #expect(CNKIExpertQueryBuilder.build(.init(query: "测试", field: "ZZ")) == "SU %= '测试'")
    }

    @Test func emptyQuery_returnsEmpty() {
        #expect(CNKIExpertQueryBuilder.build(query: "   ").isEmpty)
    }

    @Test func professionalSearchURL_isAdvSearchPage() {
        #expect(CNKIExpertQueryBuilder.professionalSearchURL.absoluteString == "https://kns.cnki.net/kns8s/AdvSearch")
    }
}
