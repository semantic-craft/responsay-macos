import Foundation

extension QuickCaptureViewModel {
    public func processText(_ text: String, outputMode: OutputMode = .coachRewrite) async {
        guard phase != .listening else { return }
        // Admit the recognizing-`.thinking` case so recognized cloud-OCR text flows straight into
        // processing without bouncing off the guard; `reset()` below clears `snapRecognizing`.
        guard phase != .thinking || snapRecognizing else { return }
        reset()
        phase = .thinking
        // Pre-formed text (selection / OCR / programmatic) routes through the text-coach lane.
        await runTransform(outputMode, text: text, using: textCoach, origin: .preformed)
    }

    func startListening(outputMode: OutputMode) {
        reset()
        activeOutputMode = outputMode
        // 560: bind the Intent-aware capture to the target that's focused NOW — before the panel or
        // a later focus change can move it — so commit can prove it's still the same target.
        if outputMode == .intentAwareDictation {
            intentCaptureStartSnapshot = intentTargetSnapshotProvider?()
        }
        do {
            (speech as? SpeechCaptureProfileConfigurable)?
                .setCaptureProfile(outputMode.spec.asrProfile)
            try speech.start(locale: locale)
            recordingStartedAt = Date()
            phase = .listening
            tasks.set(.failsafe, Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.maxListeningDuration)
                guard !Task.isCancelled, let self, self.phase == .listening else { return }
                await self.release()   // process what was captured rather than record forever
            })
            let stream = speech.levels
            tasks.set(.level, Task { [weak self] in
                for await value in stream { self?.level = value }
            })
            if let partials = (speech as? SpeechPartialTranscriptProviding)?.partialTranscripts {
                tasks.set(.partial, Task { [weak self] in
                    for await text in partials {
                        guard let self else { return }
                        self.transcript = text
                    }
                })
            }
        } catch {
            enterError(error.localizedDescription)
        }
    }

    func stopAndProcess(outputMode: OutputMode) async {
        guard phase == .listening else { return }
        let generation = captureGeneration
        tasks.cancel(.level); level = 0
        tasks.cancel(.failsafe)
        phase = .thinking
        isFinalizingTranscript = true
        var trace = LatencyTrace()
        trace.mark(.record, at: Date())  // 507: recording done, ASR about to run
        do {
            let text = try await speech.stop()
            guard captureGeneration == generation, phase == .thinking else { return }
            let transcribedAt = Date()
            trace.mark(.transcribe, at: transcribedAt)
            latencyTrace = trace  // handed to `apply` for the .polish / .insert marks
            // 568: the Intent-aware warm-cloud latency starts at this same ASR-final boundary; the
            // `.visible` end is stamped at a real insert in `commitIntentInsert`.
            if outputMode == .intentAwareDictation { intentLatencyStopMark = transcribedAt }
            tasks.cancel(.partial)
            isFinalizingTranscript = false
            // Just-spoken text routes through the speech-coach lane.
            await runTransform(outputMode, text: text, using: coach, origin: .speechFinal)
            if outputMode != .intentAwareDictation {
                offerRevertIfNeeded()
                offerCorrectionIfNeeded()
            }
        } catch {
            guard captureGeneration == generation, phase == .thinking else { return }
            latencyTrace = nil
            tasks.cancel(.partial)
            isFinalizingTranscript = false
            transcript = ""
            enterError(CaptureFailure.classify(error).userMessage)
        }
    }

    func enterError(_ message: String) {
        errorMessage = message
        phase = .error
        tasks.set(.errorDismiss, Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .error else { return }
            self.errorMessage = nil
            self.phase = .idle
        })
    }

    func reset() {
        errorMessage = nil; result = nil; captureResult = nil; intentCaptureState = nil; copiedText = ""; selectedAlternative = nil; didAutoInsertResult = false; transcript = ""; isFinalizingTranscript = false; snapRecognizing = false; level = 0; recordingStartedAt = nil
        intentReviewProposal = nil; intentReviewReverifyRejected = false
        intentCaptureStartSnapshot = nil; intentInsertionTransaction = nil; intentInsertionLifecycle = nil
        legalCandidates = []; legalResponse = nil; legalResponseRoute = nil
        legalCaseCandidates = []; isFindingCases = false
        legalSendConfirm = nil; pendingLegalCard = nil; askSession = nil
        revertableInsertion = nil
        correctionOffer = nil; correctionDraft = nil
        latencyTrace = nil; intentLatencyStopMark = nil
        captureGeneration = UUID()
        activeIntentCompilationID = nil
        inserter.beginSession()
        tasks.cancelAll()
    }
}
