import Foundation

// 375 — transform DECISIONS (CaptureResult + persistence intent) live in
// `CaptureTransformer`. This extension is now thin: set transcript, guard empty,
// then `apply` the transformer's `TextTransformOutcome` to @Observable state.
extension QuickCaptureViewModel {
    enum TransformInputOrigin { case speechFinal, preformed }

    /// The single place a transform result mutates the VM. Mirrors the former
    /// per-method captureResult / insert / save / phase blocks 1:1.
    func apply(_ outcome: TextTransformOutcome) async {
        latencyTrace?.mark(.polish, at: Date())  // 507: transform returned (≈0ms for 直写)
        switch outcome {
        case let .insert(capture, item):
            await applyInsert(capture, item: item, offersCorrection: true)
        case let .review(result, capture, item):
            latencyTrace = nil  // 507: review card, not a direct insert → no E2E latency
            self.result = result
            selectedAlternative = nil
            captureResult = capture
            try? store.save(item)
            phase = .review
        case let .failed(reason, capture, result, item):
            latencyTrace = nil
            if let result {
                self.result = result
                selectedAlternative = nil
            }
            if let capture { captureResult = capture }
            if let item { try? store.save(item) }
            enterError(reason)
        case let .autoInsertedReview(result, capture, item):
            latencyTrace = nil
            self.result = result
            selectedAlternative = nil
            captureResult = capture
            try? store.save(item)
            didAutoInsertResult = true
            phase = .review
        case let .intentInsert(capture, latency):
            await commitIntentInsert(capture, latency: latency)
        case let .intentNeedsReview(reason, proposal):
            latencyTrace = nil
            // A contested-entity review (#562) arrives with its own proposal (candidates + a
            // safe draft); anything else gets the generic confirm (no candidates/draft to
            // leak). Either way the raw transcript is held in memory only, never inserted.
            presentIntentReview(proposal ?? .generic(transcript: transcript), reason: reason)
        case let .intentSafeUnavailable(reason):
            latencyTrace = nil
            intentCaptureState = .safeUnavailable(reason)
            phase = .review
        }
    }

    /// How a single insert attempt resolved — so the Intent-aware commit (#560) can build its
    /// undo evidence only on a real insert, and record a copy/abandon terminal otherwise.
    enum InsertOutcome { case inserted, copied, failed }

    @discardableResult
    func applyInsert(
        _ capture: CaptureResult,
        item: CaptureItem?,
        offersCorrection: Bool
    ) async -> InsertOutcome {
        captureResult = capture
        // No editable target → don't paste ⌘V into the void; offer the text as a copy pill so a
        // dictation made with the cursor outside any field isn't lost. Intent-aware uses the same
        // route but deliberately omits History and correction learning in issue 556.
        let route = InsertionStrategyResolver.route(
            policy: capture.insertPolicy,
            isEditableTarget: isEditableTarget?(),
            hasText: !(capture.insertText?.isEmpty ?? true))
        if route == .copyPill, let text = capture.insertText {
            latencyTrace = nil
            copiedText = text
            correctionOffer = offersCorrection && shouldOfferCorrection(for: text) ? text : nil
            if let item { try? store.save(item) }
            phase = .copied
            return .copied
        }
        phase = .idle
        do {
            try await CaptureResultInserter.insertIfNeeded(capture, using: inserter)
            if let item { try? store.save(item) }
            flushLatency(insertedAt: Date())  // 507: .insert mark + emit
            return .inserted
        } catch {
            latencyTrace = nil
            enterError(error.localizedDescription)
            return .failed
        }
    }

    /// 507: stamp the final insert boundary and hand the completed trace to the sink.
    private func flushLatency(insertedAt: Date) {
        guard var trace = latencyTrace else { return }
        trace.mark(.insert, at: insertedAt)
        latencyTrace = nil
        latencySink?(trace)
    }

    func insertRawTranscript(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.raw(text, locale: locale))
    }

    func insertPolishedTranscript(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.polish(text, locale: locale))
    }

    func insertIntentAwareTranscript(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            return
        }
        let compilationID = UUID()
        activeIntentCompilationID = compilationID
        let outcome = await transformer.intentAware(text, locale: locale)
        guard activeIntentCompilationID == compilationID, phase == .thinking else { return }
        activeIntentCompilationID = nil
        await apply(outcome)
    }

    func rewriteAndInsert(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.rewrite(text, locale: locale))
    }

    func normalizeTypographyAndInsert(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.normalizeTypography(text, locale: locale))
    }

    func translateAndInsert(
        _ text: String,
        preview: Bool = false,
        style: TextTranslationStyle = .literal,
        useSnapTarget: Bool = false
    ) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.translate(text, preview: preview, locale: locale, style: style, useSnapTarget: useSnapTarget))
    }

    func processTranscript(_ text: String, using activeCoach: CoachAPI) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        await apply(await transformer.express(text, using: activeCoach, locale: locale))
    }

    /// The one place a mode maps to its transform. Both entry points route here — speech
    /// (`stopAndProcess`) and pre-formed text (`processText`); the only thing that varies by
    /// entry is the `CoachAPI` to use (speech coach vs text coach), passed in. Exhaustive over
    /// the mode, so a new mode must declare its routing (no silent fall-through).
    func runTransform(
        _ mode: OutputMode,
        text: String,
        using activeCoach: CoachAPI,
        origin: TransformInputOrigin
    ) async {
        switch mode {
        case .rawTranscript:
            await insertRawTranscript(text)
        case .polishedTranscript:
            await insertPolishedTranscript(text)
        case .intentAwareDictation:
            guard origin == .speechFinal else {
                await apply(.intentSafeUnavailable(reason: .invalidSource))
                return
            }
            await insertIntentAwareTranscript(text)
        case .rewriteSameLanguage:
            await rewriteAndInsert(text)
        case .normalizeTypographySelection:
            await normalizeTypographyAndInsert(text)
        case .idiomaticPreview:
            await apply(await transformer.idiomaticPreview(text, locale: locale))
        case .coachRewrite:
            await processTranscript(text, using: activeCoach)
        case .translateSpoken:
            // 听写翻译: 第一语言（母语）→ 第二语言（外语）, the fixed direction.
            await translateAndInsert(text, style: mode.spec.translateStyle ?? .literal)
        case .translateWritten:
            // 划词翻译 (editable): auto-direction via the 第一/第二语言 pair (外文→第一; 第一→第二),
            // inserted in place — so selecting foreign text translates it to 母语, not a no-op.
            await translateAndInsert(text, style: mode.spec.translateStyle ?? .literal, useSnapTarget: true)
        case .translatePreview:
            // 划词翻译 (read-only): auto-direction, card only (read-only 外文 → 母语 card).
            await translateAndInsert(text, preview: true, useSnapTarget: true)
        case .teachingFeedback:
            await processTeachingFeedback(text)
        case .askSelection:
            await processAskSelection(text)
        }
    }
}
