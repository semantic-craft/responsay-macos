import Foundation

extension QuickCaptureViewModel {
    public func prepareAskAndListen(context: String) async {
        guard phase != .listening, phase != .thinking else { return }
        let mode: SelectionAskMode =
            (evaluateScene(text: context)?.scene ?? .unknown) != .unknown ? .legal : .general
        startListening(outputMode: .askSelection)
        guard phase == .listening else { return }
        askSession = SelectionAskSession(rawSelection: context, mode: mode)
    }

    /// Re-enter ask listening for a *follow-up* on the same selection, keeping
    /// the live `askSession` so turns accumulate (real multi-turn). Returns
    /// `false` (no-op) when there's no live session or the bounded turn limit
    /// is reached. `startListening` calls `reset()` which clears `askSession`,
    /// so we restore it afterwards — same ordering as `prepareAskAndListen`.
    @discardableResult
    public func prepareFollowUpAndListen() -> Bool {
        guard phase != .listening, phase != .thinking else { return false }
        guard let continuing = askSession, !continuing.reachedTurnLimit else { return false }
        startListening(outputMode: .askSelection)
        guard phase == .listening else { return false }
        askSession = continuing
        return true
    }

    func processAskSelection(_ question: String) async {
        transcript = question
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            return
        }
        var session = askSession ?? SelectionAskSession(rawSelection: "")
        session = session.asking(question)
        do {
            // 屏幕上下文: 任意提问 is the "AI sees my screen" flow, so when enabled we lead the
            // context with the visible screen content; off → nothing screen-derived is sent.
            let screenBlock = (screenContextEnabled?() ?? true)
                ? ExpressPromptBuilder.askContextBlock(contextProvider?())
                : nil
            let context = [screenBlock, session.conversationContext()]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            let expr = try await coach.ask(question, context: context)
            let disciplined = Self.applyAskDiscipline(expr, session: session)
            askSession = session.answeringLast(disciplined.idiomatic)
            result = disciplined
            selectedAlternative = nil
            captureResult = CaptureResultFactory.coach(source: question, card: disciplined)
            try? store.save(CaptureItem(
                sourceText: question, language: locale.rawValue,
                idiomatic: activeIdiomatic, reasons: disciplined.reasons))
            phase = .review
        } catch {
            enterError(error.localizedDescription)
        }
    }

    nonisolated static func applyAskDiscipline(
        _ expr: ExpressionResult, session: SelectionAskSession
    ) -> ExpressionResult {
        guard session.mode == .legal else { return expr }
        let processor = VerificationPostProcessor()
        func disciplined(_ text: String) -> String {
            processor.ensureTags(in: text, anchors: session.guardedLegalAnchors(for: text))
        }
        return ExpressionResult(
            idiomatic: disciplined(expr.idiomatic),
            original: expr.original,
            reasons: expr.reasons,
            thinkingShift: expr.thinkingShift,
            alternatives: expr.alternatives.map(disciplined))
    }
}
