import Testing
import Foundation
@testable import ResponsayCore

/// 452 — the sensitivity classifier that decides whether auto-learn interrupts the user
/// (PRD 2026-06-19 §3). Deterministic paths (案号 regex + gazetteer) are asserted directly;
/// the NER pass is best-effort, so the suite runs it with `useNamedEntityRecognition: false`
/// except for one precedence smoke check.
@Suite struct HotwordSensitivityClassifierTests {
    private let det = HotwordSensitivityClassifier(useNamedEntityRecognition: false)

    @Test func gazetteerTermIsSpecialized() {
        #expect(det.classify("民法典") == .specialized(.legalGazetteer))
        #expect(det.classify("最高人民法院") == .specialized(.legalGazetteer))
    }

    @Test func caseNumberIsSpecialized() {
        #expect(det.classify("（2023）京01民终1234号") == .specialized(.caseNumber))
        #expect(det.classify("(2021)沪0115民初5678号") == .specialized(.caseNumber))
    }

    @Test func ordinaryWordsAreOrdinary() {
        #expect(det.classify("文档") == .ordinary)
        #expect(det.classify("今天天气不错") == .ordinary)
        #expect(det.classify("") == .ordinary)
        #expect(det.classify("   ") == .ordinary)
    }

    @Test func leadingAndTrailingWhitespaceTrimmed() {
        #expect(det.classify("  民法典 ") == .specialized(.legalGazetteer))
    }

    @Test func customGazetteerOverridesDefault() {
        let c = HotwordSensitivityClassifier(gazetteer: ["卡尔·拉伦茨"], useNamedEntityRecognition: false)
        #expect(c.classify("卡尔·拉伦茨") == .specialized(.legalGazetteer))
        #expect(c.classify("民法典") == .ordinary, "not in this custom set")
    }

    @Test func isSpecializedConvenience() {
        #expect(det.isSpecialized("民法典"))
        #expect(det.isSpecialized("（2023）京01民终1234号"))
        #expect(!det.isSpecialized("文档"))
    }

    // Case-number regex must not fire on year-like ordinary text without the 号 ending.
    @Test func caseNumberRegexIsAnchored() {
        #expect(det.classify("（2023）我们去开会") == .ordinary)
        #expect(det.classify("2023号文件") == .ordinary, "needs the （YYYY） head, not a bare 号")
    }

    // NER enabled must not regress the deterministic gazetteer hit (gazetteer is checked first).
    @Test func nerEnabledStillCatchesGazetteerFirst() {
        let c = HotwordSensitivityClassifier()  // NER on (default)
        #expect(c.classify("民法典") == .specialized(.legalGazetteer))
    }
}
