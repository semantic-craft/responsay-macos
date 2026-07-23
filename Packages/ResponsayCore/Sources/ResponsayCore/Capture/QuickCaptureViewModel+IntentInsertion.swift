import Foundation

// 560 — bind the verified Intent-aware result to the target it was captured for, and offer a safe
// undo. Commit only inserts when the target still proves to be the same one; drift degrades to a
// single safe copy. Success records short-lifecycle undo evidence that can restore the replaced
// selection or delete the verified text — but never writes the raw transcript back.
extension QuickCaptureViewModel {
    /// The single commit for a verified Intent-aware `CaptureResult`. Re-checks the bound target,
    /// inserts (idempotently, through the gated inserter) or degrades to a safe copy, then records
    /// undo evidence + an insertion-lifecycle terminal. `latency` (#568) is the fresh compile's
    /// per-stage trace; passed only on the first-pass insert (a review-confirm passes nil), and
    /// emitted as a warm-cloud sample only when the insert actually lands.
    func commitIntentInsert(_ capture: CaptureResult, latency: IntentLatencyTrace? = nil) async {
        // Target-binding gate — only when the host supplies snapshots. No provider → keep today's
        // direct behavior (tests/headless), mirroring how `isEditableTarget` degrades to insert.
        if let snapshot = intentTargetSnapshotProvider {
            if case let .safeCopy(reason) = TargetBindingEvaluator.decide(
                start: intentCaptureStartSnapshot, current: snapshot()) {
                routeIntentSafeCopy(capture, reason: reason)
                return
            }
        }
        switch await applyInsert(capture, item: nil, offersCorrection: false) {
        case .inserted:
            emitIntentLatency(compilerStages: latency, visibleAt: Date())
            recordIntentInsertion(insertedText: capture.insertText ?? "")
            persistIntentHistory(capture, outcome: .inserted)
            clearIntentSensitiveState()
        case .copied:
            // No editable target → `applyInsert` already made one safe copy; observe the terminal,
            // and offer no undo (nothing was written into a document).
            noteIntentTerminal(.abandoned)
            persistIntentHistory(capture, outcome: .copied)
            clearIntentSensitiveState()
        case .failed:
            break
        }
    }

    /// The bound target drifted (app/window/editability changed) → one safe copy, never a guess
    /// into whatever holds focus now. Idempotent: a repeat call just re-copies the same text.
    private func routeIntentSafeCopy(_ capture: CaptureResult, reason: TargetDriftReason) {
        latencyTrace = nil
        copiedText = capture.insertText ?? ""
        phase = .copied
        noteIntentTerminal(.abandoned)
        persistIntentHistory(capture, outcome: .copied)
        clearIntentSensitiveState()
    }

    /// Persist ONLY the approved Intent-aware final (#565 / spec decision 29): the verified text,
    /// its visible route and coarse outcome, with `sourceText: nil` so the raw utterance is never
    /// retained. No raw transcript / plan / side note / candidate / grounding evidence — and no
    /// change reason with content — reaches the store; the route + outcome carry the metadata.
    private func persistIntentHistory(_ capture: CaptureResult, outcome: IntentHistoryOutcome) {
        let text = (capture.insertText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? store.save(CaptureItem(
            sourceText: nil,
            language: locale.rawValue,
            idiomatic: capture.insertText ?? "",
            reasons: [],
            actionKind: .dictation,
            intentRoute: capture.intentInsertRoute,
            intentOutcome: outcome))
    }

    /// After a terminal Intent-aware outcome, drop the session's raw-bearing state (#565 / spec
    /// decision 37): the raw transcript, the raw-carrying `captureResult`, the off-screen review
    /// proposal (plan + candidates + grounding evidence) and the start snapshot. Keeps only the
    /// non-raw carriers a terminal UI still needs — the safe-undo transaction (verified text + a
    /// copy of the prior selection, captured before this runs) during its window, and the copy pill.
    func clearIntentSensitiveState() {
        transcript = ""
        captureResult = nil
        intentReviewProposal = nil
        intentReviewReverifyRejected = false
        intentCaptureStartSnapshot = nil
        intentLatencyStopMark = nil
    }

    /// 568: complete the warm-cloud latency trace (stop→visible) from the fresh compile's per-stage
    /// marks and hand it to the sink — ONLY on a first-pass verified insert. `compilerStages` is nil
    /// on the review-confirm path, and the `stop` boundary is only set for a live speech capture, so
    /// a confirm / copy / drift is never counted as a warm sample. Clears the stop mark either way.
    private func emitIntentLatency(compilerStages: IntentLatencyTrace?, visibleAt: Date) {
        defer { intentLatencyStopMark = nil }
        guard var trace = compilerStages, let stop = intentLatencyStopMark else { return }
        trace.mark(.stop, at: stop)
        trace.mark(.visible, at: visibleAt)
        intentLatencySink?(trace)
    }

    /// Record short-lifecycle undo evidence for a successful insert. The offer is only armed when a
    /// host undo executor exists; it auto-expires so a stale undo can't fire much later.
    private func recordIntentInsertion(insertedText: String) {
        noteIntentTerminal(nil)   // .inserted
        guard !insertedText.isEmpty, intentUndoExecutor != nil else { return }
        intentInsertionTransaction = IntentInsertionTransaction(
            insertedText: insertedText,
            priorSelection: intentCaptureStartSnapshot?.selection)
        tasks.set(.intentUndoExpiry, Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.revertWindow)
            guard !Task.isCancelled, let self else { return }
            self.intentInsertionTransaction = nil
            self.intentInsertionLifecycle?.recordExpired()   // honest terminal (no-op if already ended)
        })
    }

    /// Safely undo the last Intent-aware insert: delete the verified text, or restore the replaced
    /// selection — only if the inserted text is still provably present; otherwise refuse (never a
    /// raw write-back). Idempotent: the offer clears immediately, so a double-tap can't undo twice.
    public func undoIntentInsertion() async {
        guard let transaction = intentInsertionTransaction, let executor = intentUndoExecutor else { return }
        tasks.cancel(.intentUndoExpiry)
        intentInsertionTransaction = nil   // optimistic: the chip dismisses at once
        switch transaction.undoPlan(currentTargetText: intentTargetTextProvider?()) {
        case .refuse:
            // The field was edited past the insert → don't touch the document.
            noteIntentTerminal(.abandoned)
        case let plan:
            noteIntentTerminal(await executor(plan) ? .reverted : .abandoned)
        }
    }

    /// Move the intent insertion-lifecycle observer to a terminal (or initialise it at `.inserted`
    /// when `terminal` is nil). Pure observation — this ticket drives no learning off it (#565).
    private func noteIntentTerminal(_ terminal: InsertionState?) {
        if intentInsertionLifecycle == nil { intentInsertionLifecycle = InsertionLifecycle() }
        switch terminal {
        case .reverted: intentInsertionLifecycle?.recordReverted()
        case .abandoned: intentInsertionLifecycle?.recordAbandoned()
        default: break
        }
    }
}
