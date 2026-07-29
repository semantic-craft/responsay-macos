import Foundation

// MARK: - 375 TextTransformOutcome + CaptureTransformer
//
// The transform "substantial logic" lifted off QuickCaptureViewModel: the
// CaptureResult / persistence intent for raw / polish / rewrite / translate /
// express. The transformer owns the DECISIONS and returns a `TextTransformOutcome`
// descriptor; the VM's `apply(_:)` is the only place that mutates @Observable state
// (#372 sibling — like LegalCaptureCoordinator).
//
// Behaviour is preserved 1:1 from the former `+TextTransforms` methods, including
// the per-case `language` tags.

/// What the view model should do after a transform. Computed by `CaptureTransformer`,
/// applied by `QuickCaptureViewModel.apply(_:)`.
public enum TextTransformOutcome: Sendable {
    /// Build `capture`, the VM inserts it (insertIfNeeded) and persists `item`; phase → .idle.
    case insert(capture: CaptureResult, item: CaptureItem)
    /// Coach result → review: set `result` + `capture`, persist `item`; phase → .review.
    case review(result: ExpressionResult, capture: CaptureResult, item: CaptureItem)
    /// Failure: optionally set `capture`/`result` + persist `item`, then enter error.
    case failed(reason: String, capture: CaptureResult?, result: ExpressionResult?, item: CaptureItem?)
    /// Teaching stage 2: the express text was already auto-inserted, now enriched
    /// with prosody → review. Sets `result` + `capture`(+prosody), persists `item`,
    /// marks `didAutoInsertResult`, phase → .review.
    case autoInsertedReview(result: ExpressionResult, capture: CaptureResult, item: CaptureItem)
    /// Verified Intent-aware text. It intentionally carries no CaptureItem: issue 556 does not
    /// implement the nullable-source History migration, so raw intent speech must not persist.
    /// `latency` (#568) carries the compiler-stage marks of the warm-cloud latency trace; the VM
    /// completes it with the `stop`/`visible` boundaries at commit and emits it on a real insert.
    case intentInsert(capture: CaptureResult, latency: IntentLatencyTrace?)
    /// `proposal` (#562): the off-screen review context (contested entity candidates); nil for
    /// the generic confirm review. Only its `content` projection can ever be rendered.
    case intentNeedsReview(reason: IntentReviewReason, proposal: IntentReviewProposal?)
    case intentSafeUnavailable(reason: IntentUnavailableReason)
}

/// Result of the teaching/express flow (express → immediate insert → review). Distinct
/// from the 5-transform `TextTransformOutcome` because teaching auto-inserts (no review
/// gate). The prosody visualization was retired, so there is no longer a second
/// prosody-analyze pass — `review` is ready as soon as express returns.
public enum TeachingExpressStage: Sendable {
    /// API express succeeded: the VM inserts `capture` now (low latency), marks
    /// auto-inserted, then applies `review` to open the coach card.
    case expressed(capture: CaptureResult, review: TextTransformOutcome)
    /// Express itself failed → just enter error (nothing inserted/persisted).
    case failed(reason: String)
}

@MainActor
public final class CaptureTransformer {
    private let polisher: (any TextPolishAPI)?
    /// On-device punctuation for the raw/faithful path (no LLM). nil → raw stays verbatim.
    private let punctuator: (any TextPunctuator)?
    private let rewriter: (any TextRewriteAPI)?
    private let translator: (any TextTranslationAPI)?
    private let contextProvider: (@MainActor () -> ExpressionContext?)?
    /// 屏幕上下文 gate. false → no screen-derived context is sent to the cloud express paths
    /// (地道外文 / 写入并讲解); local routing keeps reading `contextProvider` directly. nil →
    /// enabled (so existing call sites and tests are unaffected).
    private let screenContextEnabled: (@MainActor () -> Bool)?
    private let translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)?
    /// 截图翻译 target, resolved per captured text (auto-direction). Used ONLY by the
    /// preview translate path (the snap & translate route); 听写/划词 keep
    /// `translationTargetProvider`. nil → fall back to 简体中文 (snap's natural default).
    private let snapTranslationTargetResolver: (@MainActor (String) -> TranslationTargetLanguage)?
    private let rewriteToneProvider: (@MainActor () -> RewriteTone)?
    private let rewriteStyleProvider: (@MainActor () -> RewriteStyle)?
    /// The 轻度润色 register nudge — the EXPLICITLY-activated 日常办公 pack only (强制清单 / 正式表达),
    /// kept SEPARATE from `rewriteStyleProvider`: the latter now resolves to the 表达升级 tier default
    /// (`.pack(expression_upgrade)`) when nothing is active, which must NOT leak into 轻度润色 (it would
    /// nudge the light tier with the heavy-rewrite skill and suppress streaming). nil → plain polish.
    private let polishStyleHintProvider: (@MainActor () -> String?)?
    private let intentCompiler: (any IntentPlanCompiler)?
    private let intentRoutePolicyProvider: (@MainActor () -> IntentRoutePolicy)?
    /// #562 — dictionary terms + confirmed aliases for the entity candidate table. Independent
    /// of the 屏幕上下文 gate (the dictionary is not screen-derived); context texts are added
    /// separately behind that gate.
    private let intentGroundingProvider: (@MainActor () -> IntentGroundingSources)?
    /// #564 — user toggle for the optional second-stage polish (default off). Off ⇒ the
    /// sanitized-draft route is the whole pipeline; nothing else changes.
    private let intentOptionalPolishEnabledProvider: (@MainActor () -> Bool)?
    /// #574 — content-free intent failure categories, forwarded into the pipeline.
    private let intentFailureSink: (@Sendable (String) -> Void)?

    public init(
        polisher: (any TextPolishAPI)?,
        rewriter: (any TextRewriteAPI)?,
        translator: (any TextTranslationAPI)?,
        contextProvider: (@MainActor () -> ExpressionContext?)?,
        screenContextEnabled: (@MainActor () -> Bool)? = nil,
        translationTargetProvider: (@MainActor () -> TranslationTargetLanguage)?,
        snapTranslationTargetResolver: (@MainActor (String) -> TranslationTargetLanguage)? = nil,
        rewriteToneProvider: (@MainActor () -> RewriteTone)?,
        rewriteStyleProvider: (@MainActor () -> RewriteStyle)?,
        polishStyleHintProvider: (@MainActor () -> String?)? = nil,
        punctuator: (any TextPunctuator)? = nil,
        intentCompiler: (any IntentPlanCompiler)? = nil,
        intentRoutePolicyProvider: (@MainActor () -> IntentRoutePolicy)? = nil,
        intentGroundingProvider: (@MainActor () -> IntentGroundingSources)? = nil,
        intentOptionalPolishEnabledProvider: (@MainActor () -> Bool)? = nil,
        intentFailureSink: (@Sendable (String) -> Void)? = nil
    ) {
        self.polisher = polisher
        self.punctuator = punctuator
        self.rewriter = rewriter
        self.translator = translator
        self.contextProvider = contextProvider
        self.screenContextEnabled = screenContextEnabled
        self.translationTargetProvider = translationTargetProvider
        self.snapTranslationTargetResolver = snapTranslationTargetResolver
        self.rewriteToneProvider = rewriteToneProvider
        self.rewriteStyleProvider = rewriteStyleProvider
        self.polishStyleHintProvider = polishStyleHintProvider
        self.intentCompiler = intentCompiler
        self.intentRoutePolicyProvider = intentRoutePolicyProvider
        self.intentGroundingProvider = intentGroundingProvider
        self.intentOptionalPolishEnabledProvider = intentOptionalPolishEnabledProvider
        self.intentFailureSink = intentFailureSink
    }

    /// The context handed to the cloud express prompt — `contextProvider`'s output, but withheld
    /// entirely when 屏幕上下文 is off so nothing screen-derived leaves the device on that path.
    private func cloudContext() -> ExpressionContext? {
        guard screenContextEnabled?() ?? true else { return nil }
        return contextProvider?()
    }

    /// The same privacy-gated snapshot, explicitly named for the post-ASR compiler boundary.
    /// Unlike recognition context injection, this may inform only verified register or source
    /// disambiguation; it cannot authorize new facts or bypass source rendering.
    private func allowedIntentContext() -> ExpressionContext? {
        cloudContext()
    }

    /// The 屏幕上下文 block (app/window/cursor/screen) for the same-language transforms
    /// (整理 / 翻译 / 改写). nil when 屏幕上下文 is off (gated via `cloudContext`).
    private func transformContext() -> String? {
        ExpressPromptBuilder.transformContextBlock(cloudContext())
    }

    // MARK: - Transforms (assume non-empty input; the VM guards empty + sets transcript)

    /// 如实输入 (verbatim). With a `punctuator` (and a model installed for an offline ASR that emits
    /// no punctuation), restore punctuation ON-DEVICE — no LLM, no rewrite. Best-effort: a missing /
    /// not-applicable punctuator returns the transcript unchanged, so raw stays exactly verbatim.
    public func raw(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        let output = await punctuator?.punctuate(text) ?? text
        return .insert(
            capture: CaptureResultFactory.raw(output),
            item: item(source: text, language: locale.rawValue, output: output, reasons: []))
    }

    public func polish(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        let styleHint = activePolishStyleHint()
        // Polish (the LLM tidy that adds punctuation) may be unavailable — no key,
        // offline, or the call fails. That must NOT kill the dictation: degrade to
        // the verbatim transcript so polished-by-default is safe with no LLM.
        var output = text
        var changes: [String] = []
        do {
            if let polished = try await polisher?.polish(text, styleHint: styleHint, context: transformContext()),
               !polished.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output = polished.text
                changes = polished.changes
            }
        } catch {
            // keep verbatim `output` — punctuation is best-effort.
        }
        return .insert(
            capture: CaptureResultFactory.polish(source: text, output: output),
            item: item(source: text, language: locale.rawValue, output: output, reasons: changes, actionKind: .polish))
    }

    public func intentAware(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        let allowedContext = allowedIntentContext()
        let (outcome, latency) = await IntentCompilationPipeline(
            compiler: intentCompiler, failureSink: intentFailureSink).compileTraced(
            finalTranscript: text,
            locale: locale,
            allowedContext: allowedContext,
            routePolicy: intentRoutePolicyProvider?() ?? .unavailable,
            grounding: intentGrounding(allowedContext: allowedContext),
            optionalPolish: intentOptionalPolisher())
        switch outcome {
        case let .insertable(text: output, route):
            return .intentInsert(capture: CaptureResultFactory.intentAware(
                source: text,
                output: output,
                route: route), latency: latency)
        case let .needsReview(reason, proposal):
            return .intentNeedsReview(reason: reason, proposal: proposal)
        case let .safeUnavailable(reason):
            return .intentSafeUnavailable(reason: reason)
        }
    }

    /// #562 — allowed grounding for entity candidates: dictionary/alias data from the injected
    /// provider, plus context text fields that ride the SAME 屏幕上下文 gate as the compiler
    /// context (`allowedIntentContext` returns nil when the toggle is off → zero context texts).
    private func intentGrounding(allowedContext: ExpressionContext?) -> IntentGroundingSources {
        let base = intentGroundingProvider?() ?? .empty
        let contextTexts = [
            allowedContext?.selectedText,
            allowedContext?.textBeforeCursor,
            allowedContext?.textAfterCursor,
            allowedContext?.visibleScreenText
        ].compactMap { $0 }
        guard !contextTexts.isEmpty else { return base }
        return IntentGroundingSources(
            dictionaryTerms: base.dictionaryTerms,
            aliases: base.aliases,
            contextTexts: base.contextTexts + contextTexts)
    }

    /// The 轻度润色 register nudge: the explicitly-activated 日常办公 pack only (强制清单 / 正式表达),
    /// via its own provider. nil when nothing is active → plain polish. (Must NOT fall back to
    /// `rewriteStyleProvider`, which now defaults to the heavy 表达升级 skill.)
    private func activePolishStyleHint() -> String? {
        polishStyleHintProvider?()
    }

    /// #564 — the optional second stage over the verified sanitized draft. Register/style hint
    /// and the gated screen-context block are resolved HERE (MainActor) and baked in, so the
    /// closure carries fixed strings: no raw side note, superseded span or grounding clue can
    /// reach the polisher, and 屏幕上下文 off means a nil context block by the same gate as
    /// every other cloud transform. Priority inside the hint follows spec decision 27
    /// (explicit user pack > App register > confirmed personal style), composed upstream.
    private func intentOptionalPolisher() -> IntentOptionalPolisher? {
        guard intentOptionalPolishEnabledProvider?() == true, let polisher else { return nil }
        let styleHint = activePolishStyleHint()
        let context = transformContext()
        return IntentOptionalPolisher(polish: { draft in
            try await polisher.polish(draft, styleHint: styleHint, context: context).text
        })
    }

    public func rewrite(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        guard let rewriter else {
            return .failed(reason: "Rewrite service is not configured.", capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
        let style = rewriteStyleProvider?() ?? .tone(rewriteToneProvider?() ?? .natural)
        do {
            let rewritten = try await rewriter.rewrite(text, style: style, context: transformContext())
            let output = rewritten.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : rewritten.text
            return .insert(
                capture: CaptureResultFactory.rewriteSelection(source: text, output: output),
                item: item(source: text, language: locale.rawValue, output: output, reasons: rewritten.changes, actionKind: .rewrite))
        } catch {
            // Persist the recognized transcript even though the transform failed, so an
            // unconfigured/erroring LLM never discards an ASR result (openless keeps every
            // session). capture stays nil — don't auto-insert raw text on a cross-language fail.
            return .failed(reason: error.localizedDescription, capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
    }

    /// 规范排版: 确定性规则整理（标点 / 全半角 / 空格）+ 指纹护栏下的薄 AI 段落重排（只拼断行），替换选区。
    /// 原文一字不改。段落重排复用注入的 `rewriter`（reflow StylePack），指纹护栏（`ChineseTypesetting.assemble`）
    /// 保证 AI 改了文字就丢弃、回退纯规则；无 rewriter 或调用失败时同样退化为纯规则整理（不 fail —— 确定性
    /// 整理无需 LLM）。移植自法墨 `FamoSelectionPublishFormatter`（2026-07-22）。
    public func normalizeTypography(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        let cleaned = ChineseTypesetting.preClean(text)
        var reflowed: String?
        if let rewriter {
            reflowed = (try? await rewriter.rewrite(cleaned, style: Self.typesettingReflowStyle, context: nil))?
                .text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let output = ChineseTypesetting.assemble(cleaned: cleaned, reflowed: reflowed)
        return .insert(
            capture: CaptureResultFactory.rewriteSelection(source: text, output: output),
            item: item(source: text, language: locale.rawValue, output: output, reasons: [], actionKind: .rewrite))
    }

    public func idiomaticPreview(_ text: String, locale: CaptureLocale) async -> TextTransformOutcome {
        guard let rewriter else {
            return .failed(reason: "Idiomatic expression service is not configured.", capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
        do {
            let rewritten = try await rewriter.rewrite(text, style: Self.selectionIdiomaticStyle, context: transformContext())
            let output = rewritten.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : rewritten.text
            let result = ExpressionResult(idiomatic: output, original: text, reasons: [])
            return .review(
                result: result,
                capture: CaptureResultFactory.coach(source: text, card: result),
                item: item(source: text, language: locale.rawValue, output: output, reasons: [], actionKind: .coach))
        } catch {
            return .failed(reason: error.localizedDescription, capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
    }

    public func translate(
        _ text: String,
        preview: Bool,
        locale: CaptureLocale,
        style: TextTranslationStyle = .literal,
        useSnapTarget: Bool = false
    ) async -> TextTransformOutcome {
        guard let translator else {
            return .failed(reason: "Translation service is not configured.", capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
        // 截图翻译 resolves its own auto-direction target (外文→中文); 听写/划词/选区翻译 keep the shared
        // 中文→外文 target. Keyed off the output mode (via `useSnapTarget`), NOT off `preview` —
        // read-only 划词翻译 is also a preview but must keep the shared target.
        let target = useSnapTarget
            ? (snapTranslationTargetResolver?(text) ?? .chineseSimplified)
            : (translationTargetProvider?() ?? .englishUS)
        do {
            // 截图翻译 (useSnapTarget) reads OCR'd screenshot text — the live focused-window context
            // would be unrelated noise, so skip it there; 听写/划词翻译 keep the 屏幕上下文 block.
            let context = useSnapTarget ? nil : transformContext()
            let translated = try await translator.translate(text, target: target, style: style, context: context)
            let output = translated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : translated.text
            let capture = preview
                ? CaptureResultFactory.translatePreview(source: text, output: output)
                : CaptureResultFactory.translateSelection(source: text, output: output)
            if preview {
                return .review(
                    result: ExpressionResult(idiomatic: output, original: text, reasons: translated.notes),
                    capture: capture,
                    item: item(source: text, language: "translate:\(target.rawValue)", output: output, reasons: translated.notes, actionKind: .translate))
            }
            return .insert(
                capture: capture,
                item: item(source: text, language: "translate:\(target.rawValue)", output: output, reasons: translated.notes, actionKind: .translate))
        } catch {
            // Persist the recognized transcript even though the transform failed, so an
            // unconfigured/erroring LLM never discards an ASR result (openless keeps every
            // session). capture stays nil — don't auto-insert raw text on a cross-language fail.
            return .failed(reason: error.localizedDescription, capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
    }

    public func express(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TextTransformOutcome {
        do {
            let target = translationTargetProvider?() ?? .englishUS
            let expr = try await coach.express(text, context: cloudContext(), target: target)
            return .review(
                result: expr,
                capture: CaptureResultFactory.coach(source: text, card: expr),
                item: item(source: text, language: locale.rawValue, output: expr.idiomatic, reasons: expr.reasons, actionKind: .coach))
        } catch {
            // Persist the recognized transcript even though the transform failed, so an
            // unconfigured/erroring LLM never discards an ASR result (openless keeps every
            // session). capture stays nil — don't auto-insert raw text on a cross-language fail.
            return .failed(reason: error.localizedDescription, capture: nil, result: nil,
                item: item(source: text, language: locale.rawValue, output: text, reasons: []))
        }
    }

    // MARK: - Teaching mode (375 — express → insert → review)

    /// 写入并讲解 (teachingFeedback): express the intent, then hand back both the capture to
    /// insert immediately and the review outcome to open the coach card. The prosody-analyze
    /// second stage was retired with the prosody visualization, so this is a single LLM call.
    public func teachingExpress(_ text: String, using coach: CoachAPI, locale: CaptureLocale) async -> TeachingExpressStage {
        do {
            let target = translationTargetProvider?() ?? .englishUS
            let expr = try await coach.express(text, context: cloudContext(), target: target)
            let capture = CaptureResultFactory.expressInEnglish(
                source: text, insertText: expr.idiomatic, coachCard: expr, target: target)
            let review = TextTransformOutcome.autoInsertedReview(
                result: expr,
                capture: capture,
                item: item(source: text, language: locale.rawValue, output: expr.idiomatic,
                           reasons: expr.reasons, actionKind: .coach))
            return .expressed(capture: capture, review: review)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// 381 — every CaptureItem is built here, so the success paths stamp the exact
    /// `actionKind` (raw→dictation, polish→polish, rewrite→rewrite, translate→translate,
    /// express/coach→coach, analysis/practice→feedback). Failure fallbacks keep the
    /// default `.dictation` (the preserved raw transcript, openless-style).
    private func item(
        source: String, language: String, output: String, reasons: [String],
        actionKind: TextActionKind = .dictation
    ) -> CaptureItem {
        CaptureItem(sourceText: source, language: language, idiomatic: output, reasons: reasons, actionKind: actionKind)
    }

    /// 规范排版的「段落重排」reflow 风格：只把硬换行拆断的行拼回段落、一字不改（系统提示词见
    /// `ChineseTypesetting.reflowSystemPrompt`）。复用 `rewriter` 走这个 pack，指纹护栏兜底改字风险。
    private static let typesettingReflowStyle = RewriteStyle.pack(StylePack(
        id: "style.normative_typography_reflow.cn",
        name: "规范排版·段落重排",
        systemPrompt: ChineseTypesetting.reflowSystemPrompt,
        origin: .builtIn))

    private static let selectionIdiomaticStyle = RewriteStyle.pack(StylePack(
        id: "style.selection_idiomatic_preview.en",
        name: "选区地道表达",
        systemPrompt: [
            "Rewrite the selected English text into a more natural, idiomatic English paraphrase.",
            "Keep the same meaning, stance, names, numbers, deadlines, citations, and terminology.",
            "Do not translate. Do not teach, explain, critique, add alternatives, or add notes.",
            "Return one clean result; if the original is already natural, make the smallest useful change.",
            "Use an empty changes array."
        ].joined(separator: "\n"),
        origin: .builtIn))

}
