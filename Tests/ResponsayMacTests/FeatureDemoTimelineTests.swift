import XCTest
@testable import ResponsayMac

/// Onboarding feature-demo-loop choreography. The timeline is pure (`DemoTimeline.state(for:at:)`),
/// so we assert the product-critical beats here — above all 选区命令's "preview before write".
/// Test standard T1: no UI host and no network.
final class FeatureDemoTimelineTests: XCTestCase {

    private func state(_ kind: FeatureDemoKind, _ t: Double) -> DemoFrameState {
        DemoTimeline.state(for: kind, at: t, script: .script(for: kind))
    }

    // MARK: - Selection command: listen, preview, then write

    func testCoachPreviewIsShownBeforeAnyReplacement() {
        // While the review panel is up and the ⏎ action is highlighted, the user's text must NOT
        // yet be replaced — the capsule shows a previewable result first.
        let preview = state(.coach, 5800)            // panel up, primary active (5660…6080)
        XCTAssertTrue(preview.panelOpacity > 0.5, "review panel should be visible during preview")
        XCTAssertTrue(preview.panelPrimaryActive, "⏎ should be highlighted during the preview beat")
        XCTAssertFalse(preview.contentReplaced, "selection must stay intact until after ⏎")
        XCTAssertTrue(preview.selectScale > 0.5, "the selection stays highlighted while previewing")
    }

    func testCoachReplacesOnlyAfterTheEnterBeat() {
        XCTAssertFalse(state(.coach, 6149).contentReplaced)
        XCTAssertTrue(state(.coach, 6150).contentReplaced, "replacement happens at the ⏎ beat (6150ms)")
        XCTAssertEqual(state(.coach, 6149).selectScale, 1, accuracy: 0.001)  // selection fully shown right up to replacement
    }

    func testCoachPillIsThinkingDuringRewrite() {
        let mid = state(.coach, 3500)
        XCTAssertEqual(mid.pillMode, .thinking)
        XCTAssertEqual(mid.pillLabel, FeatureDemoScript.coach.thinkingLabel)  // 改写中…
        XCTAssertTrue(mid.pillOpacity > 0.5, "capsule should be on screen mid-rewrite")
    }

    func testCoachListensForSelectionRewriteCommand() {
        // 选中文本改写 is the real write-back path (`.rewriteSelection` → replaceSelection), a
        // configurable shortcut — NOT Fn Space (which is read-only 任意提问). The demo must not
        // label the write-back rewrite as Fn Space.
        let listening = state(.coach, 2500)
        XCTAssertEqual(listening.hotkeyText, "改写选区键")
        XCTAssertNotEqual(listening.hotkeyText, "Fn Space", "Fn Space is read-only ask, never write-back")
        XCTAssertEqual(listening.pillMode, .listening)
        XCTAssertEqual(listening.pillLabel, FeatureDemoScript.coach.listeningLabel)
        XCTAssertTrue(listening.waveActive)
        XCTAssertFalse(listening.pillTime.isEmpty, "selection command recording shows the elapsed timer")
    }

    func testCoachPanelHiddenAtLoopStart() {
        XCTAssertEqual(state(.coach, 0).panelOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(state(.coach, 0).pillOpacity, 0, accuracy: 0.001)
        XCTAssertFalse(state(.coach, 0).contentReplaced)
    }

    // MARK: - Dictate: listen → finalize → DIRECT insert (no review panel)

    func testDictateNeverShowsAReviewPanel() {
        for t in stride(from: 0.0, to: FeatureDemoKind.dictate.durationMs, by: 200) {
            XCTAssertEqual(state(.dictate, t).panelOpacity, 0, accuracy: 0.001,
                           "dictation writes directly; no preview panel at t=\(t)")
        }
    }

    func testDictateListensThenThinks() {
        let listening = state(.dictate, 2000)
        XCTAssertEqual(listening.pillMode, .listening)
        XCTAssertFalse(listening.pillTime.isEmpty, "listening shows an elapsed timer")
        XCTAssertTrue(listening.waveActive)
        XCTAssertEqual(state(.dictate, 4500).pillMode, .thinking)  // polishing after 3840
    }

    func testDictateTranscriptIsMonotonicAndComplete() {
        let n = FeatureDemoScript.dictate.wordTokens.count
        var last = 0
        for t in stride(from: 1200.0, through: 5000, by: 100) {
            let c = state(.dictate, t).wordCount
            XCTAssertGreaterThanOrEqual(c, last, "word count must not go backwards")
            XCTAssertLessThanOrEqual(c, n, "word count must not exceed the token list")
            last = c
        }
        XCTAssertEqual(last, n, "all phrases revealed before finalizing")
        XCTAssertTrue(state(.dictate, 5500).contentReplaced, "final text inserted after 5120ms")
    }

    // MARK: - Translate: listen in Chinese → write English (NO preview panel)

    func testTranslateListensThenWritesInPlaceWithoutPanel() {
        let listening = state(.translate, 2000)
        XCTAssertEqual(listening.hotkeyText, "Fn Shift")
        XCTAssertEqual(listening.pillMode, .listening)
        XCTAssertTrue(listening.waveActive)
        XCTAssertFalse(state(.translate, 5119).contentReplaced)
        XCTAssertTrue(state(.translate, 5120).contentReplaced, "translation writes in place at 5120ms")
        XCTAssertTrue(FeatureDemoScript.translate.target.contains("revised NDA"),
                      "translate demo needs concrete replacement text for the final frame")
        for t in stride(from: 0.0, through: 7000.0, by: 250.0) {
            XCTAssertEqual(state(.translate, t).panelOpacity, 0, accuracy: 0.001,
                           "translate streams directly; no preview panel at t=\(t)")
            XCTAssertFalse(state(.translate, t).panelPrimaryActive,
                           "translate has no ⏎ beat at t=\(t)")
        }
        XCTAssertEqual(state(.translate, 4500).pillLabel, FeatureDemoScript.translate.thinkingLabel)
    }

    // MARK: - Ask Anything: listen → answer/action panel → commit

    func testEnglishListensThenReplaces() {
        XCTAssertEqual(state(.english, 2500).pillMode, .listening)
        XCTAssertEqual(state(.english, 5000).pillMode, .thinking)
        XCTAssertFalse(state(.english, 6419).contentReplaced)
        XCTAssertTrue(state(.english, 6420).contentReplaced, "answer/action result lands at 6420ms")
        XCTAssertTrue(state(.english, 5600).panelOpacity > 0.5, "answer/action panel shown before commit")
        XCTAssertEqual(state(.english, 1000).hotkeyText, "Fn Space")
        XCTAssertTrue(FeatureDemoScript.english.reason.contains("搜索开关"))
    }

    // MARK: - Select-translate (选区翻译 · 只读): selection → command → read-only card, no write-back

    func testSelectTranslatePrepShowsSelectionAndCommandBeforeCard() {
        let prep = state(.selectTranslate, 2500)
        XCTAssertTrue(prep.selectScale > 0.5, "the selected legal text is highlighted while listening")
        XCTAssertEqual(prep.hotkeyText, "Fn Space")
        XCTAssertEqual(prep.pillMode, .listening)
        XCTAssertEqual(prep.pillLabel, FeatureDemoScript.selectTranslate.listeningLabel)
        XCTAssertTrue(prep.waveActive)
        XCTAssertEqual(prep.panelOpacity, 0, accuracy: 0.01, "result card is not up yet during prep")
    }

    func testSelectTranslateResultCardIsReadOnly() {
        let card = state(.selectTranslate, 5200)   // == reducedTimeMs: result card up
        XCTAssertTrue(card.panelOpacity > 0.5, "the English result card is visible")
        XCTAssertFalse(card.contentReplaced, "translate is read-only: the source is never auto-replaced")
        XCTAssertTrue(card.selectScale > 0.5, "the original selection stays intact behind the card")
    }

    func testSelectTranslateNeverReplacesContent() {
        for t in stride(from: 0.0, through: FeatureDemoKind.selectTranslate.durationMs, by: 200) {
            XCTAssertFalse(state(.selectTranslate, t).contentReplaced,
                           "read-only translate must never replace the source at t=\(t)")
        }
    }

    func testSelectTranslateMirrorsRealReadOnlyAskCard() {
        // The real 任意提问 selection path returns a read-only Global Voice Assistant answer card
        // (复制 / 朗读 / 追问 — AnswerActionBar). The demo's only takeaway action is 复制; there is
        // no write-back affordance, because the real card does not auto-insert into the document.
        let s = FeatureDemoScript.selectTranslate
        XCTAssertEqual(s.primaryAction, "复制", "the takeaway action is read-only copy, not write-back")
        XCTAssertFalse(s.reason.contains("写回"), "the demo must not promise a write-back feature we don't ship")
    }

    func testSelectTranslateReducedFrameShowsReadOnlyCard() {
        let s = state(.selectTranslate, FeatureDemoKind.selectTranslate.reducedTimeMs)
        XCTAssertTrue(s.panelOpacity > 0.5, "reduced frame rests on the result card")
        XCTAssertFalse(s.contentReplaced, "reduced frame keeps the source intact (read-only)")
        XCTAssertTrue(FeatureDemoScript.selectTranslate.target.contains("governing law"),
                      "result card needs concrete English translation text for the static frame")
    }

    // MARK: - Reduce Motion: each kind's static frame is a representative beat

    func testReducedFrameShowsARepresentativeResult() {
        // Selection command pauses on the *preview*; Ask Anything likewise mid-answer.
        XCTAssertTrue(state(.coach, FeatureDemoKind.coach.reducedTimeMs).panelOpacity > 0.5)
        XCTAssertFalse(state(.coach, FeatureDemoKind.coach.reducedTimeMs).contentReplaced)
        XCTAssertTrue(state(.english, FeatureDemoKind.english.reducedTimeMs).panelOpacity > 0.5)
        // Dictate / translate pause on the inserted result.
        XCTAssertTrue(state(.dictate, FeatureDemoKind.dictate.reducedTimeMs).contentReplaced)
        XCTAssertTrue(state(.translate, FeatureDemoKind.translate.reducedTimeMs).contentReplaced)
    }

    func testEveryDemoHasAVisibleOutcomeToastLabel() {
        for kind in FeatureDemoKind.allCases {
            XCTAssertFalse(kind.outcomeToast.isEmpty, "\(kind) should name the visible result moment")
        }
    }

    // MARK: - Easing helpers

    func testEasingPrimitives() {
        XCTAssertEqual(DemoTimeline.p(5, 0, 10), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DemoTimeline.p(-5, 0, 10), 0, accuracy: 1e-9)   // clamped
        XCTAssertEqual(DemoTimeline.p(50, 0, 10), 1, accuracy: 1e-9)   // clamped
        XCTAssertEqual(DemoTimeline.easeOut(0), 0, accuracy: 1e-9)
        XCTAssertEqual(DemoTimeline.easeOut(1), 1, accuracy: 1e-9)
        XCTAssertEqual(DemoTimeline.lerp(16, 0, 0.5), 8, accuracy: 1e-9)
        XCTAssertEqual(DemoTimeline.easeInOut(0.5), 0.5, accuracy: 1e-9)
    }

    func testWindowedFadesInHoldsAndOut() {
        XCTAssertEqual(DemoTimeline.windowed(0, 100, 200, 800, 900), 0, accuracy: 1e-9)   // before
        XCTAssertEqual(DemoTimeline.windowed(500, 100, 200, 800, 900), 1, accuracy: 1e-9) // held
        XCTAssertEqual(DemoTimeline.windowed(1000, 100, 200, 800, 900), 0, accuracy: 1e-9) // after
    }

    func testMMSSFormatting() {
        XCTAssertEqual(DemoTimeline.mmss(0), "00:00")
        XCTAssertEqual(DemoTimeline.mmss(2400), "00:02")
        XCTAssertEqual(DemoTimeline.mmss(-50), "00:00")  // clamped
    }

    // MARK: - Verify (来源核验): anchors reveal, both sources are searched, sources return

    func testVerifyAnchorsRevealProgressively() {
        XCTAssertEqual(state(.verify, 3000).anchorRevealCount, 0, "no anchors before 3200ms")
        XCTAssertEqual(state(.verify, 3500).anchorRevealCount, 1, "first anchor at 3200ms")
        XCTAssertEqual(state(.verify, 4000).anchorRevealCount, 2, "second anchor at 3700ms")
    }

    func testVerifySearchPageFlashesAfterAnchorClick() {
        XCTAssertEqual(state(.verify, 5000).searchPageOpacity, 0, accuracy: 0.01)
        XCTAssertTrue(state(.verify, 5800).searchPageOpacity > 0.5,
                      "first source search should be visible around 5800ms")
        XCTAssertTrue(state(.verify, 7200).searchPageOpacity > 0.5,
                      "second source search should also be visible")
        XCTAssertEqual(state(.verify, 8700).searchPageOpacity, 0, accuracy: 0.01,
                       "search page fades out before source cards return")
    }

    func testVerifySearchesBothXiongWeiAndSongXuguang() {
        let xiong = state(.verify, 5900)
        XCTAssertEqual(xiong.searchFocusIndex, 0)
        XCTAssertGreaterThanOrEqual(xiong.matchRevealCount, 2,
                                    "Xiong Wei search should reveal matched fields")

        let song = state(.verify, 7400)
        XCTAssertEqual(song.searchFocusIndex, 1)
        XCTAssertGreaterThanOrEqual(song.matchRevealCount, 2,
                                    "Song Xuguang search should reveal matched fields")
    }

    func testVerifySourcesReturnAfterSearch() {
        XCTAssertEqual(state(.verify, 8300).verifiedSourceRevealCount, 0,
                       "sources should not appear until after both search beats")
        XCTAssertEqual(state(.verify, 8600).verifiedSourceRevealCount, 1,
                       "first source card appears after the searches")
        XCTAssertEqual(state(.verify, 9400).verifiedSourceRevealCount, 2,
                       "second source card follows so the demo shows the verification effect")
    }

    func testVerifySelectionStaysVisible() {
        XCTAssertTrue(state(.verify, 2000).selectScale > 0.5, "selection highlighted during extract")
        XCTAssertTrue(state(.verify, 5000).selectScale > 0.5, "selection stays during anchor display")
    }

    func testVerifyReducedFrameShowsVerifiedSources() {
        let s = state(.verify, FeatureDemoKind.verify.reducedTimeMs)
        XCTAssertEqual(s.verifiedSourceRevealCount, 2, "reduced frame should show returned source cards")
        XCTAssertTrue(s.panelOpacity > 0.5, "panel visible at reduced frame")
    }

    // MARK: - Keywords (检索关键词): groups reveal, then CNKI query

    func testKeywordsGroupsRevealSequentially() {
        XCTAssertEqual(state(.keywords, 2800).keywordRevealCount, 0)
        XCTAssertEqual(state(.keywords, 3200).keywordRevealCount, 1)
        XCTAssertEqual(state(.keywords, 3600).keywordRevealCount, 2)
        XCTAssertEqual(state(.keywords, 4000).keywordRevealCount, 3)
    }

    func testKeywordsCNKIQueryAppearsAfterGroups() {
        XCTAssertEqual(state(.keywords, 4300).queryOpacity, 0, accuracy: 0.01,
                       "query not yet visible while groups are revealing")
        XCTAssertTrue(state(.keywords, 5000).queryOpacity > 0.5,
                      "CNKI query visible after all groups revealed")
    }

    func testKeywordsReducedFrameShowsQuery() {
        let s = state(.keywords, FeatureDemoKind.keywords.reducedTimeMs)
        XCTAssertTrue(s.keywordRevealCount == 3, "all 3 groups visible at reduced frame")
        XCTAssertTrue(s.queryOpacity > 0.5, "CNKI query visible at reduced frame")
    }

    func testKeywordsInsertBeatHasVisibleQueryText() {
        XCTAssertFalse(FeatureDemoScript.keywords.target.isEmpty,
                       "插入检索式 demo 的最后一帧必须能看到具体插入内容")
        XCTAssertTrue(FeatureDemoScript.keywords.target.contains("SU=("))
        XCTAssertFalse(state(.keywords, 5799).contentReplaced)
        XCTAssertTrue(state(.keywords, 5800).contentReplaced, "query is inserted at the ⏎ beat")
    }

    // MARK: - Fallback (搜索引擎兜底): extended thinking, URL results

    func testFallbackURLsRevealProgressively() {
        XCTAssertEqual(state(.fallback, 3400).urlRevealCount, 0, "no URLs before panel")
        XCTAssertEqual(state(.fallback, 3800).urlRevealCount, 1, "first URL at 3600ms")
        XCTAssertEqual(state(.fallback, 4500).urlRevealCount, 2, "second URL at 4200ms")
    }

    func testFallbackExtendedThinkingPhase() {
        let early = state(.fallback, 2500)
        XCTAssertTrue(early.pillOpacity > 0.5, "pill visible during extended search")
        XCTAssertEqual(early.pillMode, .thinking)
        XCTAssertEqual(early.panelOpacity, 0, accuracy: 0.01, "no results yet during thinking")
    }

    func testFallbackReducedFrameShowsURLs() {
        let s = state(.fallback, FeatureDemoKind.fallback.reducedTimeMs)
        XCTAssertTrue(s.urlRevealCount > 0, "reduced frame shows at least one URL")
        XCTAssertTrue(s.panelOpacity > 0.5, "panel visible at reduced frame")
    }

    // MARK: - Verify: 划词菜单 pops over the selection, 来源核验 highlights, then it fades to the jump

    func testVerifyMenuPopsAndHighlightsBeforeAnchors() {
        XCTAssertTrue(state(.verify, 2000).menuOpacity > 0.5, "划词菜单 visible over the selection")
        XCTAssertTrue(state(.verify, 2300).menuHighlight, "来源核验 row highlights as it's chosen")
        XCTAssertEqual(state(.verify, 3200).menuOpacity, 0, accuracy: 0.01,
                       "menu fades before the anchor reveal — existing extract/search beats untouched")
        XCTAssertEqual(state(.verify, 3500).anchorRevealCount, 1, "anchor beats still start at 3200ms")
    }

    func testVerifyJumpShowsXiongWeiOriginalAsMatch() {
        // The signature: the CNKI jump must carry Xiong Wei's real paper coordinates so the demo
        // visibly shows "跳到知网看熊伟原文" (the user's explicit ask).
        let xiong = SourceVerificationExamples.xiongWeiPaper
        guard case let .anchors(items) = FeatureDemoScript.verify.resultContent, let first = items.first else {
            return XCTFail("verify demo must carry anchor items for the CNKI page")
        }
        XCTAssertTrue(first.resultTitle.contains("国家创新体系中财税法"), "matched hit is Xiong Wei's paper title")
        XCTAssertTrue(first.resultMeta.contains("熊伟"), "the hit names 熊伟 as the author")
        XCTAssertTrue(first.resultMeta.contains("现代法学"), "the hit names the journal 《现代法学》")
        XCTAssertEqual(first.searchQuery, xiong.query, "search field uses the real extracted query")
        XCTAssertFalse(first.matchFields.isEmpty, "the jump ticks off verifiable match fields")
    }

    // MARK: - Snap OCR (截图识别): drag-select region → recognize → result panel

    func testSnapOCRMarqueeThenRecognizeThenPanel() {
        XCTAssertEqual(state(.snapOCR, 400).marqueeScale, 0, accuracy: 0.01, "no marquee at the very start")
        XCTAssertTrue(state(.snapOCR, 1700).marqueeScale > 0.5, "drag-select marquee grows in")
        let thinking = state(.snapOCR, 3500)
        XCTAssertEqual(thinking.pillMode, .thinking)
        XCTAssertEqual(thinking.pillLabel, FeatureDemoScript.snapOCR.thinkingLabel)  // 识别中…
        XCTAssertTrue(thinking.pillOpacity > 0.5, "recognizing pill visible")
        XCTAssertTrue(state(.snapOCR, 5500).panelOpacity > 0.5, "OCR result panel appears after recognition")
    }

    func testSnapOCRExtractedTextDrivesToast() {
        XCTAssertFalse(state(.snapOCR, 4000).contentReplaced)
        XCTAssertTrue(state(.snapOCR, 5000).contentReplaced, "extracted text drives the 已取字 toast")
        XCTAssertEqual(FeatureDemoKind.snapOCR.outcomeToast, "已取字")
        XCTAssertFalse(FeatureDemoScript.snapOCR.target.isEmpty, "OCR result panel needs the extracted text")
    }

    func testSnapOCRReducedFrameShowsPanel() {
        let s = state(.snapOCR, FeatureDemoKind.snapOCR.reducedTimeMs)
        XCTAssertTrue(s.panelOpacity > 0.5, "reduced frame rests on the OCR result panel")
        XCTAssertTrue(s.marqueeScale > 0.5, "marquee still visible at the result frame")
    }
}
