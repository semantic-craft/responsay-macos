import Testing
import Foundation
@testable import ResponsayCore

/// A guaranteed-decodable model output: encode a real `LegalSkillResponse` (envelope
/// fields are overwritten by the validator, so their values here don't matter).
func legalGoodOutputJSON(summary: String = "已生成证据论证矩阵") -> String {
    let resp = LegalSkillResponse(
        runId: "model-ignored", skillId: "model-ignored",
        scene: .litigation, stage: .briefDrafting,
        summary: summary,
        cards: [.cnkiQuery(CNKIQueryCard(title: "检索式", expertQuery: "SU=('违约')"))],
        verificationAnchors: [])
    return String(data: try! JSONEncoder().encode(resp), encoding: .utf8)!
}

/// 106 — LegalOutputValidator: decode → one repair pass → fallback. Never crashes.
struct LegalOutputValidatorTests {
    private let validator = LegalOutputValidator()
    private let env = LegalOutputValidator.Envelope(
        runId: "r1", skillId: "s1", scene: .litigation, stage: .briefDrafting)

    @Test func success_decodesModelOutput_envelopeInjected() async {
        var repairCalls = 0
        let r = await validator.validate(rawOutput: legalGoodOutputJSON(), envelope: env) { _ in
            repairCalls += 1; return ""
        }
        #expect(repairCalls == 0)                  // valid first pass → no repair
        #expect(r.summary == "已生成证据论证矩阵")
        #expect(r.runId == "r1")                    // envelope wins over model values
        #expect(r.skillId == "s1")
        #expect(r.scene == .litigation)
        if case .cnkiQuery = r.cards.first {} else { Issue.record("expected cnkiQuery card") }
        #expect(r.warnings.isEmpty)
    }

    @Test func repair_recoversFromMalformedFirstPass() async {
        var repairCalls = 0
        let r = await validator.validate(rawOutput: "{ not json ,,", envelope: env) { _ in
            repairCalls += 1; return legalGoodOutputJSON(summary: "修复后")
        }
        #expect(repairCalls == 1)
        #expect(r.summary == "修复后")
    }

    @Test func fallback_whenRepairAlsoFails_neverCrashesNeverInserts() async {
        let r = await validator.validate(rawOutput: "{ bad", envelope: env) { _ in "still { bad" }
        if case let .fallbackText(card) = r.cards.first {
            #expect(card.text.contains("bad"))
        } else {
            Issue.record("expected fallbackText card")
        }
        #expect(r.warnings.isEmpty == false)
        #expect(r.insertables.isEmpty)              // never a fabricated insert
        #expect(r.summary.contains("降级"))
    }

    @Test func decode_toleratesMissingInsertablesAndWarnings() async {
        // A well-shaped reply that omits the empty insertables/warnings arrays must still
        // decode to a real card — not get pushed to fallback (live finding).
        var repairCalls = 0
        let json = #"{"summary":"ok","cards":[{"cnkiQuery":{"title":"t","expertQuery":"SU=('x')"}}],"verificationAnchors":[]}"#
        let r = await validator.validate(rawOutput: json, envelope: env) { _ in repairCalls += 1; return "" }
        #expect(repairCalls == 0)
        #expect(r.summary == "ok")
        if case .cnkiQuery = r.cards.first {} else { Issue.record("expected cnkiQuery, got fallback") }
        #expect(r.insertables.isEmpty)   // defaulted, not failed
    }

    @Test func decode_realisticModelMatrixOutput_decodesToStructured() async {
        // Locks in the live-validated shape (anchor A): externally-tagged matrix card +
        // label/kind/status anchors + omitted empty arrays → decodes structured, NOT fallback.
        let json = """
        {"summary":"已生成证据论证矩阵",
         "cards":[{"evidenceArgumentMatrix":{"title":"证据论证链","rows":[
           {"id":"r1","claim":"被告应担责","legalElement":"违约行为","factToProve":"未付款",
            "evidence":"[缺口]","authenticity":"unknown","legality":"unknown","relevance":"strong",
            "probativeForce":"unknown","rebuttalRisk":"否认","gapFilling":"调取合同",
            "verificationAnchorIds":["a1"]}]}}],
         "verificationAnchors":[{"id":"a1","label":"《民法典》第577条","kind":"law",
            "status":"pending","query":"民法典 577","preferredSources":[]}]}
        """
        let r = await validator.validate(rawOutput: json, envelope: env) { _ in "" }
        guard case let .evidenceArgumentMatrix(card) = r.cards.first else {
            Issue.record("expected evidenceArgumentMatrix, got fallback/other"); return
        }
        #expect(card.rows.first?.relevance == .strong)
        #expect(r.verificationAnchors.first?.kind == .law)
        #expect(r.verificationAnchors.first?.status == .pending)
    }

    @Test func stripsCodeFences() async {
        let fenced = "```json\n" + legalGoodOutputJSON(summary: "去围栏") + "\n```"
        let r = await validator.validate(rawOutput: fenced, envelope: env) { _ in "" }
        #expect(r.summary == "去围栏")
    }
}
