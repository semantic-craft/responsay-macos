import Testing
import Foundation
@testable import ResponsayCore

// 375 — the transform decisions (CaptureResult/persistence intent) tested on
// the collaborator directly, without a view model.
@MainActor
private final class ThrowingPolish: TextPolishAPI {
    func polish(_ text: String) async throws -> PolishResult { throw CoachAPIError.message("no LLM") }
}

private struct StubPunctuator: TextPunctuator {
    let transform: @Sendable (String) -> String
    func punctuate(_ text: String) async -> String { transform(text) }
}

@MainActor
private final class RecordingRewriter: TextRewriteAPI {
    var lastStyle: RewriteStyle?
    func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        lastStyle = style
        return PolishResult(text: "Could you get back to me by this afternoon?", original: text, changes: ["ignored"])
    }
}

@MainActor
private final class RecordingTranslator: TextTranslationAPI {
    var lastTarget: TranslationTargetLanguage?
    func translate(_ text: String, target: TranslationTargetLanguage, style: TextTranslationStyle) async throws -> TranslationResult {
        lastTarget = target
        return TranslationResult(text: "OUT", original: text, targetLanguage: target.rawValue)
    }
}

@MainActor
private func transformer(
    polisher: (any TextPolishAPI)? = nil,
    rewriter: (any TextRewriteAPI)? = nil,
    translator: (any TextTranslationAPI)? = nil,
    punctuator: (any TextPunctuator)? = nil
) -> CaptureTransformer {
    CaptureTransformer(
        polisher: polisher, rewriter: rewriter, translator: translator,
        contextProvider: nil, translationTargetProvider: nil,
        rewriteToneProvider: nil, rewriteStyleProvider: nil,
        punctuator: punctuator)
}

// 如实输入 with no punctuator → exactly verbatim (raw stays raw).
@Test @MainActor func transformer_raw_noPunctuator_isVerbatim() async {
    let outcome = await transformer().raw("今天天气不错我们去图书馆", locale: .chinese)
    guard case let .insert(capture, item) = outcome else { Issue.record("expected .insert, got \(outcome)"); return }
    #expect(capture.insertText == "今天天气不错我们去图书馆")
    #expect(item.idiomatic == "今天天气不错我们去图书馆")
}

// 如实输入 WITH an on-device punctuator → punctuation is restored (no LLM), and the inserted
// text + history reflect the punctuated result while sourceText keeps the raw transcript.
@Test @MainActor func transformer_raw_appliesPunctuator() async {
    let punct = StubPunctuator { _ in "今天天气不错，我们去图书馆。" }
    let outcome = await transformer(punctuator: punct).raw("今天天气不错我们去图书馆", locale: .chinese)
    guard case let .insert(capture, item) = outcome else { Issue.record("expected .insert, got \(outcome)"); return }
    #expect(capture.insertText == "今天天气不错，我们去图书馆。")
    #expect(item.sourceText == "今天天气不错我们去图书馆")   // raw kept as the source
    #expect(item.idiomatic == "今天天气不错，我们去图书馆。")  // punctuated is what landed
}

// polish must degrade to the verbatim transcript when the LLM polish is
// unavailable — this is what makes "auto-punctuate by default" safe offline.
@Test @MainActor func transformer_polish_degradesToVerbatim_whenPolisherThrows() async {
    let outcome = await transformer(polisher: ThrowingPolish()).polish("今天没有模型", locale: .chinese)
    guard case let .insert(capture, item) = outcome else { Issue.record("expected .insert, got \(outcome)"); return }
    #expect(capture.insertText == "今天没有模型")
    #expect(item.idiomatic == "今天没有模型")
}

@Test @MainActor func transformer_rewrite_failsWhenNoRewriter() async {
    guard case let .failed(reason, _, _, _) = await transformer().rewrite("x", locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(reason.contains("Rewrite"))
}

@Test @MainActor func transformer_idiomaticPreview_returnsResultOnly() async {
    let rewriter = RecordingRewriter()
    let outcome = await transformer(rewriter: rewriter)
        .idiomaticPreview("Please reply me before today afternoon.", locale: .english)
    guard case let .review(result, capture, item) = outcome else { Issue.record("expected .review"); return }
    #expect(result.idiomatic == "Could you get back to me by this afternoon?")
    #expect(result.reasons.isEmpty)
    #expect(result.thinkingShift.isEmpty)
    #expect(result.alternatives.isEmpty)
    #expect(capture.insertPolicy == InsertPolicy.noInsert)
    #expect(item.reasons.isEmpty)
    #expect(item.actionKind == TextActionKind.coach)
    guard case let .pack(pack) = rewriter.lastStyle else { Issue.record("expected fixed style pack"); return }
    #expect(pack.systemPrompt.contains("Do not teach"))
}

@Test @MainActor func transformer_translate_failsWhenNoTranslator() async {
    guard case let .failed(reason, _, _, _) = await transformer().translate("x", preview: false, locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
    #expect(reason.contains("Translation"))
}

// 截图翻译 (snap) resolves its OWN auto-direction target (here forced to 中文), not the shared
// 听写/划词 target — even though both translate calls pass preview: true.
@Test @MainActor func translate_snapPath_usesSnapResolverTarget() async {
    let translator = RecordingTranslator()
    let t = CaptureTransformer(
        polisher: nil, rewriter: nil, translator: translator,
        contextProvider: nil,
        translationTargetProvider: { .german },
        snapTranslationTargetResolver: { _ in .chineseSimplified },
        rewriteToneProvider: nil, rewriteStyleProvider: nil)
    _ = await t.translate("Hello world", preview: true, locale: .english, useSnapTarget: true)
    #expect(translator.lastTarget == .chineseSimplified)
}

// Read-only 划词翻译 is ALSO preview: true, but must keep the shared 中文→外文 target —
// the snap resolver must NOT hijack it (regression: target was keyed off `preview`).
@Test @MainActor func translate_selectionPreview_keepsSharedTarget() async {
    let translator = RecordingTranslator()
    let t = CaptureTransformer(
        polisher: nil, rewriter: nil, translator: translator,
        contextProvider: nil,
        translationTargetProvider: { .german },
        snapTranslationTargetResolver: { _ in .chineseSimplified },
        rewriteToneProvider: nil, rewriteStyleProvider: nil)
    _ = await t.translate("你好世界", preview: true, locale: .chinese, useSnapTarget: false)
    #expect(translator.lastTarget == .german)
}

// the coach path lands in review (no auto-insert) with the model's idiomatic result.
@Test @MainActor func transformer_express_landsInReview_fromCoach() async {
    let coach = MockCoachAPI(result: ExpressionResult(idiomatic: "I see.", original: "我懂了", reasons: ["更自然"]))
    let outcome = await transformer().express("我懂了", using: coach, locale: .chinese)
    guard case let .review(result, _, _) = outcome else { Issue.record("expected .review, got \(outcome)"); return }
    #expect(result.idiomatic == "I see.")
}

// MARK: - 375 teaching slice (express → insert → review; prosody-analyze retired)

// teaching express, API path: express ok → `.expressed(capture, review)`. The capture is
// ready for the VM to insert immediately; the review opens the coach card from the same
// express result (no second prosody-analyze pass).
@Test @MainActor func transformer_teachingExpress_apiPath_yieldsExpressedWithReview() async {
    let coach = MockCoachAPI(result: ExpressionResult(idiomatic: "Let me check.", original: "我看看", reasons: ["更口语"]))
    guard case let .expressed(capture, review) = await transformer().teachingExpress("我看看", using: coach, locale: .chinese) else {
        Issue.record("expected .expressed"); return
    }
    #expect(capture.insertText == "Let me check.")
    guard case let .autoInsertedReview(result, reviewCapture, _) = review else {
        Issue.record("expected .autoInsertedReview"); return
    }
    #expect(result.idiomatic == "Let me check.")
    #expect(result.reasons == ["更口语"])
    #expect(reviewCapture.insertText == "Let me check.")
}

// teaching express, express itself fails → `.failed` (nothing inserted).
@Test @MainActor func transformer_teachingExpress_failsWhenExpressThrows() async {
    let coach = MockCoachAPI(error: .message("backend down"))
    guard case .failed = await transformer().teachingExpress("我看看", using: coach, locale: .chinese) else {
        Issue.record("expected .failed"); return
    }
}
