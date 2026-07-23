import Foundation

public struct IntentCompilationPipeline: Sendable {
    private let compiler: (any IntentPlanCompiler)?
    /// #568 — injectable clock for the latency trace (`compileTraced`). Production stamps `Date()`;
    /// tests inject fixed dates. Defaulted so every existing call site is unchanged.
    private let now: @Sendable () -> Date
    /// #574 — content-free failure category sink ("verify-invalidRelationship",
    /// "decode-typeMismatch", "compiler-http"…). Release builds log NOTHING below the
    /// transport layer without this, which made five real-Mac blocked cards undiagnosable
    /// from screenshots alone. Category names come from enum cases only — never the
    /// transcript, plan, or provider response (spec decision 29).
    private let failureSink: (@Sendable (String) -> Void)?

    public init(
        compiler: (any IntentPlanCompiler)?,
        now: @Sendable @escaping () -> Date = { Date() },
        failureSink: (@Sendable (String) -> Void)? = nil
    ) {
        self.compiler = compiler
        self.now = now
        self.failureSink = failureSink
    }

    /// Behaviour-only entry (unchanged signature): the compilation outcome, discarding the trace.
    /// Existing callers (`IntentProviderContractRunner`, tests) keep reading just the outcome.
    public func compile(
        finalTranscript: String,
        locale: CaptureLocale,
        allowedContext: ExpressionContext?,
        routePolicy: IntentRoutePolicy,
        grounding: IntentGroundingSources = .empty,
        optionalPolish: IntentOptionalPolisher? = nil
    ) async -> IntentCompilationOutcome {
        await compileTraced(
            finalTranscript: finalTranscript,
            locale: locale,
            allowedContext: allowedContext,
            routePolicy: routePolicy,
            grounding: grounding,
            optionalPolish: optionalPolish).outcome
    }

    /// #568 — the SAME compilation, plus an `IntentLatencyTrace` stamping the stages actually
    /// reached (the warm-cloud latency gate, AC7/AC8). `stop`/`visible` are the caller's (the VM's)
    /// boundaries — ASR-final → text visible — added around this call. Only a reached stage is
    /// stamped: a `safeUnavailable`/`needsReview` short-circuit leaves the render + guard stages
    /// unmarked, so a non-inserted outcome never counts as a warm sample. Compilation behaviour is
    /// byte-identical to `compile` — the marks are purely additive.
    public func compileTraced(
        finalTranscript: String,
        locale: CaptureLocale,
        allowedContext: ExpressionContext?,
        routePolicy: IntentRoutePolicy,
        grounding: IntentGroundingSources = .empty,
        optionalPolish: IntentOptionalPolisher? = nil
    ) async -> (outcome: IntentCompilationOutcome, latency: IntentLatencyTrace) {
        var trace = IntentLatencyTrace()

        guard routePolicy == .injectedCompiler, let compiler else {
            failureSink?(IntentUnavailableReason.compilerUnavailable.rawValue)
            return (.safeUnavailable(reason: .compilerUnavailable), trace)
        }

        let sourceUnits = IntentSourceSegmenter.segment(finalTranscript)
        guard !sourceUnits.isEmpty else {
            failureSink?(IntentUnavailableReason.invalidSource.rawValue)
            return (.safeUnavailable(reason: .invalidSource), trace)
        }
        // #562 — the whitelist entity table is built ON DEVICE before the compiler sees
        // anything; the compiler can only select these IDs, never author values or slots.
        let entityCandidates = IntentEntityCandidateTable.build(
            transcript: finalTranscript, units: sourceUnits, grounding: grounding)
        let input = IntentCompilerInput(
            finalTranscript: finalTranscript,
            locale: locale,
            allowedContext: allowedContext,
            routePolicy: routePolicy,
            sourceUnits: sourceUnits,
            entityCandidates: entityCandidates)

        let data: Data
        do {
            data = try await compiler.compile(input)
            guard !Task.isCancelled else { return (.safeUnavailable(reason: .cancelled), trace) }
        } catch {
            // Classify by error *type* only — no provider message reaches the reason (#559).
            // "no key" → compilerUnavailable, "bad response" → invalidPlan, unreachable →
            // compilerFailed; a compiler that pre-classified (capability/timeout) wins.
            let reason = IntentUnavailableReason.classify(compilerError: error)
            failureSink?("compiler-\(reason.rawValue)")
            return (.safeUnavailable(reason: reason), trace)
        }
        trace.mark(.compile, at: now())   // #568: provider call returned (the dominant latency term)

        let plan: IntentPlan
        do {
            plan = try JSONDecoder().decode(IntentPlan.self, from: data)
        } catch let error as DecodingError {
            failureSink?("decode-\(Self.decodeCase(error))")
            return (.safeUnavailable(reason: .invalidPlan), trace)
        } catch {
            failureSink?("decode-other")
            return (.safeUnavailable(reason: .invalidPlan), trace)
        }
        let verified: IntentPlanVerifier.VerifiedPlan
        do {
            verified = try IntentPlanVerifier.verify(
                plan, sourceUnits: sourceUnits, transcript: finalTranscript,
                entityCandidates: entityCandidates)
        } catch let error as IntentPlanVerifier.VerificationError {
            failureSink?("verify-\(String(describing: error))")
            return (.safeUnavailable(reason: .invalidPlan), trace)
        } catch {
            failureSink?("verify-other")
            return (.safeUnavailable(reason: .invalidPlan), trace)
        }
        trace.mark(.planVerify, at: now())

        // #562 — a selection on a contested slot cannot auto-normalize (唯一或弃权): stop in
        // review with the whole candidate group. First-pass only; a capsule confirm resolves it.
        if let contested = IntentEntityConflictArbiter.review(
            verified: verified, transcript: finalTranscript) {
            return (contested, trace)
        }
        // #575 — grounding marked but nothing selected (weak-model slip): candidate-confirm
        // review instead of a dead blocked card; auto-insert with vanished clues stays barred.
        if let unresolved = IntentEntityConflictArbiter.unresolvedGroundingReview(
            verified: verified, transcript: finalTranscript) {
            return (unresolved, trace)
        }

        // #561 preflight veto rides inside the shared finalize tail: an obvious cue the plan
        // did not explain stops in review. A structural failure above stays safe-unavailable
        // regardless of preflight — a miss authorizes nothing (spec decision 22).
        let outcome = IntentPlanFinalizer.finalize(
            verified: verified,
            cueHits: IntentCuePreflight.scan(transcript: finalTranscript, units: sourceUnits))

        guard case let .insertable(sanitizedDraft, route) = outcome else {
            return (outcome, trace)   // needsReview / safeUnavailable: no render+guard sample
        }
        // `finalize` rendered the sanitized draft AND passed the post-render guard before returning
        // insertable. Stamp both safety marks at that boundary; a shed optional polish then leaves
        // the two marks adjacent (0ms gap) and `optionalPolish` absent — the allowed degradation.
        let finalizeDone = now()
        trace.mark(.sourceRender, at: finalizeDone)

        // #564 — optional second stage: polish the verified sanitized draft only. Any failure
        // (guard, throw, cancellation) keeps the sanitized draft — enhancement may fail, safety may
        // not, and the raw transcript is unreachable from here either way.
        guard let optionalPolish else {
            trace.mark(.postRenderGuard, at: finalizeDone)
            return (outcome, trace)
        }
        let polished = try? await optionalPolish.polish(sanitizedDraft)
        trace.mark(.optionalPolish, at: now())
        guard let polished, !Task.isCancelled,
              IntentPostPolishGuard.accepts(
                  polished: polished, sanitizedDraft: sanitizedDraft, verified: verified)
        else {
            trace.mark(.postRenderGuard, at: now())
            return (outcome, trace)   // sanitized draft (polish shed / rejected)
        }
        trace.mark(.postRenderGuard, at: now())
        return (.insertable(text: polished, route: route), trace)
    }

    /// DecodingError case name only — its associated context can quote provider payload
    /// fragments, which must never reach a log (spec decision 29).
    private static func decodeCase(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch: return "typeMismatch"
        case .valueNotFound: return "valueNotFound"
        case .keyNotFound: return "keyNotFound"
        case .dataCorrupted: return "dataCorrupted"
        @unknown default: return "unknown"
        }
    }
}
