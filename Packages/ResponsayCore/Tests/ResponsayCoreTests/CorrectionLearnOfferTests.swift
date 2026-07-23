import Testing
import Foundation
@testable import ResponsayCore

// 518 — the capsule「纠正…」offer: a successful direct dictation insert offers a correction entry
// point when the text plausibly contains a mis-heard proper noun (a shaped ASCII token — user
// feedback 2026-07-03: showing it on every single dictation was too noisy). Tapping it moves the
// inserted text into a draft the mini panel edits. Unlike Revert (P0b) it does NOT require the AI
// to have changed the text — a mishear can sit in a verbatim insert too — and it does not depend
// on a reverter being wired.
@MainActor
private func tmpStore() -> FileCaptureStore {
    FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
}

@Test @MainActor func polishedDictation_offersCorrection() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "我说的是 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        polisher: MockTextPolishAPI(result: PolishResult(text: "我说的是 Metapocalypse。", original: "我说的是 Metapocalypse")))

    vm.push(outputMode: .polishedTranscript)
    await vm.release()

    #expect(vm.correctionOffer == "我说的是 Metapocalypse。")
}

@Test @MainActor func rawDictation_alsoOffersCorrection_unlikeRevert() async throws {
    // 如实输入的误识别同样需要纠正入口——revert 的「AI 改过才出现」条件不适用于这里。
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "逐字上屏 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer == "逐字上屏 Metapocalypse")
    #expect(vm.revertableInsertion == nil)
}

@Test @MainActor func beginCorrection_movesOfferIntoDraft_dismissClearsBoth() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "词是 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    vm.beginCorrection()
    #expect(vm.correctionDraft == "词是 Metapocalypse")

    vm.dismissCorrection()
    #expect(vm.correctionDraft == nil)
    #expect(vm.correctionOffer == nil)
}

@Test @MainActor func beginCorrection_withoutOffer_isANoOp() async throws {
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(), coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.beginCorrection()
    #expect(vm.correctionDraft == nil)
}

// MARK: - 复制卡合并纠正 (copy-correct merge pill)
//
// New contract (user 2026-07-05): the copy pill (`.copied`, no editable target) becomes the
// 方案A card. When the copied text plausibly holds a mis-heard proper noun, the card offers
// 纠正 alongside 复制 — the correction flow only teaches the dictionary (it never re-inserts),
// so offering it on clipboard-only text is honest. Plain text → 复制 only. (Replaces the old
// 1.3.36 contract where copied text never offered correction.)

@Test @MainActor func copyPill_offersCorrection_whenTextIsMishearShaped() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "逐字上屏 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        isEditableTarget: { false })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.phase == .copied)
    #expect(vm.copiedText == "逐字上屏 Metapocalypse")
    #expect(vm.correctionOffer == "逐字上屏 Metapocalypse")   // 纠正 shows in the copy card
}

@Test @MainActor func copyPill_plainChinese_offersCopyOnly() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        isEditableTarget: { false })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.phase == .copied)
    #expect(vm.correctionOffer == nil)   // no shaped token → 复制 only, no 纠正 button
}

@Test @MainActor func copyPill_alwaysShowSetting_offersCorrectionForPlainChinese() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气很好"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        isEditableTarget: { false },
        correctionChipAlwaysShow: { true })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.phase == .copied)
    #expect(vm.correctionOffer == "今天天气很好")
}

@Test @MainActor func beginCorrection_fromCopiedPill_exitsCopiedIntoDraft() async throws {
    // Tapping 纠正 in the copy card must leave `.copied` so the keyable correction panel (which
    // only shows while phase == .idle) can take over. The text was already auto-copied, so
    // dropping the copy card loses nothing.
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "逐字上屏 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        isEditableTarget: { false })

    vm.push(outputMode: .rawTranscript)
    await vm.release()
    #expect(vm.phase == .copied)

    vm.beginCorrection()
    #expect(vm.phase == .idle)
    #expect(vm.copiedText == "")
    #expect(vm.correctionDraft == "逐字上屏 Metapocalypse")
}

@Test @MainActor func dismissCopied_clearsCorrectionOffer_noStaleChip() async throws {
    // The copy card's own dismiss (5s / 📋) must not leave a stale offer that would resurface as
    // a separate 纠正 chip once phase returns to idle.
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "逐字上屏 Metapocalypse"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        isEditableTarget: { false })

    vm.push(outputMode: .rawTranscript)
    await vm.release()
    #expect(vm.correctionOffer != nil)

    vm.dismissCopied()
    #expect(vm.phase == .idle)
    #expect(vm.correctionOffer == nil)
}

@Test @MainActor func startingANewCapture_clearsCorrectionState() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "第一段 DeepSeek"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()
    #expect(vm.correctionOffer != nil)
    vm.beginCorrection()

    vm.push(outputMode: .rawTranscript)   // a new capture invalidates the stale offer + draft
    #expect(vm.correctionOffer == nil)
    #expect(vm.correctionDraft == nil)
}

// MARK: - Mishear-shape gate (user feedback 2026-07-03: quiet by default)

@Test @MainActor func plainChineseWithNoShapedTerm_doesNotOfferCorrection() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气不错，我们出去走走吧"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer == nil)   // no shaped/proper-noun-looking token → stays quiet
}

@Test @MainActor func digitHyphenTerm_isAlsoAMishearShape() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "试试 Qwen3-ASR 这个模型"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer != nil)
}

@Test @MainActor func interiorCapTerm_isAlsoAMishearShape() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "推荐一个模型叫 DeepSeek"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter())

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer != nil)
}

@Test @MainActor func alwaysShowSetting_offersCorrectionEvenForPlainChinese() async throws {
    // 设置里的「每次听写都显示」开关:打开后绕过形状门,任何一句话都能手动纠正。
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气不错"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        correctionChipAlwaysShow: { true })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer == "今天天气不错")
}

@Test @MainActor func alwaysShowSettingOff_stillAppliesTheShapeGate() async throws {
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "今天天气不错"
    let vm = QuickCaptureViewModel(
        speech: speech, coach: MockCoachAPI(), store: tmpStore(),
        inserter: MockTextInserter(),
        correctionChipAlwaysShow: { false })

    vm.push(outputMode: .rawTranscript)
    await vm.release()

    #expect(vm.correctionOffer == nil)
}
