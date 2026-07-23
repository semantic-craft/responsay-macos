import Foundation

/// #567 — the opt-in provider contract runner (Testing Decision 16). Runs a fixed batch of
/// requests through the SAME `IntentCompilationPipeline` a real capture uses and tallies the
/// external outcome classes, so the default cloud provider and a local provider can be held to one
/// gate: a compliant provider produces a structured plan for ≥99% of a fixed corpus, the rest stop
/// in safe review / unavailable, and a plain-text response can NEVER auto-insert.
///
/// The runner is content-free: it counts outcome classes only — never a transcript, key, or the
/// provider's raw response. The offline path (a stub compiler) proves the runner deterministically
/// with zero network; the live path (a real `DirectIntentPlanAPI`) is gated on credentials and,
/// when they are absent, is reported as NOT RUN rather than faked as passing.
public struct IntentProviderContractRunner: Sendable {
    public struct Request: Sendable {
        public let transcript: String
        public let locale: CaptureLocale
        public let grounding: IntentGroundingSources

        public init(
            transcript: String,
            locale: CaptureLocale = .chinese,
            grounding: IntentGroundingSources = .empty
        ) {
            self.transcript = transcript
            self.locale = locale
            self.grounding = grounding
        }
    }

    public struct Tally: Sendable, Equatable {
        /// A verified plan produced an auto-insertable draft.
        public let insertable: Int
        /// A recoverable ambiguity stopped safely in review.
        public let needsReview: Int
        /// The compiler / plan / guard was unusable — safe, non-inserting.
        public let safeUnavailable: Int
        public let total: Int

        public init(insertable: Int, needsReview: Int, safeUnavailable: Int, total: Int) {
            self.insertable = insertable
            self.needsReview = needsReview
            self.safeUnavailable = safeUnavailable
            self.total = total
        }

        /// Fraction of requests that produced a verified, insertable plan.
        public var structuralValidRate: Double {
            total == 0 ? 0 : Double(insertable) / Double(total)
        }

        /// Everything that did not auto-insert stayed safe (review or unavailable) — by
        /// construction, since the pipeline has only these three external outcomes.
        public var safeRest: Int { needsReview + safeUnavailable }
    }

    public init() {}

    /// Run every request through the real pipeline and tally external outcomes.
    public static func run(
        compiler: any IntentPlanCompiler,
        requests: [Request],
        routePolicy: IntentRoutePolicy = .injectedCompiler
    ) async -> Tally {
        let pipeline = IntentCompilationPipeline(compiler: compiler)
        var insertable = 0, needsReview = 0, safeUnavailable = 0
        for request in requests {
            switch await pipeline.compile(
                finalTranscript: request.transcript,
                locale: request.locale,
                allowedContext: nil,
                routePolicy: routePolicy,
                grounding: request.grounding
            ) {
            case .insertable: insertable += 1
            case .needsReview: needsReview += 1
            case .safeUnavailable: safeUnavailable += 1
            }
        }
        return Tally(
            insertable: insertable, needsReview: needsReview,
            safeUnavailable: safeUnavailable, total: requests.count)
    }

    /// The release gate over a tally: a compliant provider keeps structural validity at or above
    /// `minValidRate` over a non-empty batch. Everything that did not auto-insert is, by
    /// construction, a safe review/unavailable outcome (`run()` counts only the three external
    /// outcomes) — the "zero plain-text passthrough" guarantee is structural (the deterministic
    /// renderer is the ONLY path to `insertable`) and is exercised directly by feeding a plain-text
    /// provider and asserting `tally.insertable == 0`, not by a self-fulfilling tally field.
    public static func passesGate(_ tally: Tally, minValidRate: Double = 0.99) -> Bool {
        tally.total > 0 && tally.structuralValidRate >= minValidRate
    }
}
