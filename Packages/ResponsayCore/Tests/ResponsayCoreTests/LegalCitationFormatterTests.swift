import Testing
import Foundation
@testable import ResponsayCore

/// 189 — LegalCitationFormatter: 《法学引注手册》(2019) 体例.
struct LegalCitationFormatterTests {
    private let f = LegalCitationFormatter()

    // §61 — 行文 序数 → Arabic, 项 drops 括号; spaces collapse.
    @Test func lawProse_arabicizesTail_dropsItemParens() {
        #expect(f.lawProse("《公司法》（2013年修正）第二十七条第二款第（三）项")
                == "《公司法》（2013年修正）第27条第2款第3项")
        #expect(f.lawProse("《民法典》第五百七十七条") == "《民法典》第577条")
        #expect(f.lawProse("《个保法》第 24 条") == "《个保法》第24条")
    }

    // §61.3 — 序数 inside the law NAME is NOT Arabic-ized (only the trailing reference is).
    @Test func lawProse_preservesNameInternalOrdinals() {
        #expect(f.lawProse("《全国人大常委会关于〈婚姻法〉第二十二条的解释》第三条")
                == "《全国人大常委会关于〈婚姻法〉第二十二条的解释》第3条")
    }

    // §71 案号 → 圆括号 ; §64 文件号 → 六角括号. The single most-confused distinction.
    @Test func brackets_caseRound_docHexagon() {
        #expect(f.caseNumber("(1998)海行初字第142号") == "（1998）海行初字第142号")
        #expect(f.caseNumber("〔1998〕海行初字第142号") == "（1998）海行初字第142号")
        #expect(f.documentNumber("国发（2007）19号") == "国发〔2007〕19号")
        #expect(f.documentNumber("法释(2018)1号") == "法释〔2018〕1号")
    }

    @Test func abbreviate_outerOnly_keepsNested() {
        #expect(f.abbreviateLawName("《中华人民共和国治安管理处罚法》") == "《治安管理处罚法》")
        let nested = "《最高人民法院关于适用〈中华人民共和国刑事诉讼法〉的解释》"
        #expect(f.abbreviateLawName(nested) == nested)   // nested 中华人民共和国 preserved
    }

    @Test func chineseNumerals() {
        #expect(LegalCitationFormatter.chineseToInt("五百七十七") == 577)
        #expect(LegalCitationFormatter.chineseToInt("二十三") == 23)
        #expect(LegalCitationFormatter.chineseToInt("十") == 10)
        #expect(LegalCitationFormatter.chineseToInt("一百零五") == 105)
        #expect(LegalCitationFormatter.chineseToInt("条") == nil)
    }

    // Non-mutating conformance on an anchor (stored label stays source-matching for tagging).
    @Test func anchor_conformantLabel_doesNotMutateStored() {
        let a = VerificationAnchor(id: "x", label: "《公司法》第二十七条第（三）项", kind: .law, query: "x")
        #expect(a.conformantLabel() == "《公司法》第27条第3项")
        #expect(a.label == "《公司法》第二十七条第（三）项")
        let caseA = VerificationAnchor(id: "c", label: "(2021)京01民终1234号", kind: .caseLaw, query: "c")
        #expect(caseA.conformantLabel() == "（2021）京01民终1234号")
    }
}
