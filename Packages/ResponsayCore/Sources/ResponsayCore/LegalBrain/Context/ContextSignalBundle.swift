import Foundation

/// The assembled, explainable signal bundle handed to the scene router (104),
/// replacing a raw `ExpressionContext` (issue 113). Codable so it can be logged /
/// inspected. `verificationTargets` carries the `[待核]` coordinates (165/108);
/// `generatedAt` is injected for determinism.
public struct ContextSignalBundle: Codable, Sendable, Equatable {
    public let expressionContext: ExpressionContext
    public let appProfile: AppContextProfile
    public let urlSignal: URLSignal?
    public let headingSignals: [HeadingSignal]
    public let verificationTargets: [VerificationTarget]
    public let confidenceHints: [String]
    public let generatedAt: Date

    public init(
        expressionContext: ExpressionContext,
        appProfile: AppContextProfile,
        urlSignal: URLSignal? = nil,
        headingSignals: [HeadingSignal] = [],
        verificationTargets: [VerificationTarget] = [],
        confidenceHints: [String] = [],
        generatedAt: Date
    ) {
        self.expressionContext = expressionContext
        self.appProfile = appProfile
        self.urlSignal = urlSignal
        self.headingSignals = headingSignals
        self.verificationTargets = verificationTargets
        self.confidenceHints = confidenceHints
        self.generatedAt = generatedAt
    }

    public var hasSelection: Bool {
        guard let text = expressionContext.selectedText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One deterministic signal producer.
public protocol ContextSignalProducing: Sendable {}

/// Orchestrates the producers (114/115/116) into a `ContextSignalBundle` and
/// fuses it (117) into the built `SceneStageClassification`. Deterministic,
/// no-LLM, Foundation-only.
public struct ContextSignalLayer: Sendable {
    private let appProfiler: AppContextProfiler
    private let urlClassifier: BrowserURLClassifier
    private let headingDetector: HeadingDetector
    private let scorer: ContextConfidenceScorer

    public init(
        appProfiler: AppContextProfiler = AppContextProfiler(),
        urlClassifier: BrowserURLClassifier = BrowserURLClassifier(),
        headingDetector: HeadingDetector = HeadingDetector(),
        scorer: ContextConfidenceScorer = ContextConfidenceScorer()
    ) {
        self.appProfiler = appProfiler
        self.urlClassifier = urlClassifier
        self.headingDetector = headingDetector
        self.scorer = scorer
    }

    /// Assemble the bundle from raw context + the URL `CaptureGateContextReader`
    /// already read. `now` is injected (no `Date()` in core).
    public func assemble(
        context: ExpressionContext,
        browserURL: String? = nil,
        verificationTargets: [VerificationTarget] = [],
        now: Date
    ) -> ContextSignalBundle {
        let appProfile = appProfiler.profile(context)
        let urlSignal = browserURL.map { urlClassifier.classify($0) }
        let headingSignals = headingDetector.detect(
            textBeforeCursor: context.textBeforeCursor, windowTitle: context.windowTitle
        )
        let hints = headingSignals.map(\.reason)
        return ContextSignalBundle(
            expressionContext: context,
            appProfile: appProfile,
            urlSignal: urlSignal,
            headingSignals: headingSignals,
            verificationTargets: verificationTargets,
            confidenceHints: hints,
            generatedAt: now
        )
    }

    /// Fuse an assembled bundle into the built scene/stage classification.
    public func classify(_ bundle: ContextSignalBundle) -> SceneStageClassification {
        scorer.classify(
            appProfile: bundle.appProfile,
            headingSignals: bundle.headingSignals,
            urlSignal: bundle.urlSignal,
            hasSelection: bundle.hasSelection
        )
    }
}
