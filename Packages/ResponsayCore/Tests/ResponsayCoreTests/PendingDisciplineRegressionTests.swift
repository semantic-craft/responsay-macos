import Testing
import Foundation
@testable import ResponsayCore

/// 170 — `[待核]` discipline regression guard. Pins the cross-cutting invariants so a
/// future change to any one path can't silently break the others (138 / 142 / 155 / 165–166).
struct PendingDisciplineRegressionTests {

    // 142: the legal translation profile preserves [待核]; non-legal profiles never inject it.
    @Test func translationLegalProfile_preservesPending() {
        let legal = TranslationProfileConfig(profile: .legal)
        #expect(legal.preservesPendingCoordinates)
        #expect(legal.resolvedDirective().contains("[待核]"))

        let general = TranslationProfileConfig(profile: .general)
        #expect(!general.preservesPendingCoordinates)
        #expect(!general.resolvedDirective().contains("[待核]"))
    }

    // 165/166: a target is pending → [待核] until verified; a verified state only comes from a flip.
    @Test func verificationTarget_verifiedOnlyAfterVerification() {
        let target = VerificationTarget(id: "1", label: "《民法典》第577条", kind: .statute)
        #expect(target.status == .pending)
        #expect(target.displayLabel.contains("[待核]"))
        #expect(target.markedVerified().displayLabel.contains("[已核]"))
        // A raw pending status never reads as verified.
        #expect(VerificationOutcome(.pending) == .pending)
    }

    // 155: selection-ask legal answers keep any new law/case/date coordinate [待核].
    @Test func selectionAskLegal_keepsNewCoordinatesPending() {
        let session = SelectionAskSession(rawSelection: "案情概要……", mode: .legal)
        let anchors = session.guardedLegalAnchors(for: "依据《民法典》第577条，被告应承担继续履行的违约责任。")
        #expect(!anchors.isEmpty)
        #expect(anchors.allSatisfy { $0.status == .pending })
    }

    // 138: the non-legal (expression/coaching) path does not process legal sources at all.
    @Test func nonLegalAskPath_doesNotTouchLegalSources() {
        let session = SelectionAskSession(rawSelection: "案情概要……", mode: .general)
        #expect(session.guardedLegalAnchors(for: "依据《民法典》第577条……").isEmpty)
    }

    // MARK: 297 — the live insert path must not drop [待核] on the way to the host.

    // ensureTags(in:anchors:) tags pending/unanchored coordinates, skips settled ones,
    // and never double-tags.
    @Test func ensureTags_tagsPendingSkipsSettled_idempotent() {
        let processor = VerificationPostProcessor()
        let body = "依据《民法典》第577条与《民法典》第584条，被告应承担违约责任。"

        // No anchors → everything defaults pending → both tagged.
        let allTagged = processor.ensureTags(in: body, anchors: [])
        #expect(allTagged.contains("第577条[待核]"))
        #expect(allTagged.contains("第584条[待核]"))

        // 577 already verified → only 584 gets the tag.
        let extractor = FactCoordinateExtractor()
        let labels = extractor.extract(from: body).map(\.label)
        let verified577 = labels.filter { $0.contains("第577条") }.map {
            VerificationAnchor(id: "a", label: $0, kind: .law, status: .verifiedLaw, query: $0)
        }
        #expect(!verified577.isEmpty)
        let partial = processor.ensureTags(in: body, anchors: verified577)
        #expect(!partial.contains("第577条[待核]"))
        #expect(partial.contains("第584条[待核]"))

        // Idempotent: running again changes nothing.
        #expect(processor.ensureTags(in: allTagged, anchors: []) == allTagged)
    }

    // End-to-end: insertLegalText (the ReviewCardView onInsert target) lands tagged
    // text in the inserter even when the model body carried no inline tags —
    // previously it inserted the raw text and the host saw an untagged version.
    @Test @MainActor func insertLegalText_landsPendingTagsInHost() async {
        let speech = MockSpeechCaptureService()
        let coach = MockCoachAPI(result: nil, error: nil)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let inserter = MockTextInserter()
        let vm = QuickCaptureViewModel(
            speech: speech, coach: coach, store: FileCaptureStore(fileURL: url), inserter: inserter)

        await vm.insertLegalText("依据《民法典》第577条，被告应承担继续履行的违约责任。")

        #expect(inserter.inserted.count == 1)
        #expect(inserter.inserted.first?.contains("《民法典》第577条[待核]") == true)
    }

    // 猎虫④ F5 — 「插入检索式」(kind .query, containsPending: false) 是检索表达式
    // 不是断言正文：打标会把 SU=('《民法典》第577条') 的 CNKI 语法毁掉。
    @Test @MainActor func insertLegalText_querySkipsTagging() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let inserter = MockTextInserter()
        let vm = QuickCaptureViewModel(
            speech: MockSpeechCaptureService(), coach: MockCoachAPI(),
            store: FileCaptureStore(fileURL: url), inserter: inserter)

        await vm.insertLegalText("SU=('《民法典》第577条')", skipsTagging: true)

        #expect(inserter.inserted == ["SU=('《民法典》第577条')"])
    }
}
