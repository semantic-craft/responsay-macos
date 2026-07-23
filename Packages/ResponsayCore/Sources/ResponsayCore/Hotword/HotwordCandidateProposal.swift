import Foundation

public struct HotwordCandidateProposal: Sendable, Equatable, Codable {
    public let term: String
    public let source: HotwordLearningSource
    public let confidence: Double
    public let reason: String
    public let sourceTerm: String?
    public let appName: String?
    public let windowTitle: String?

    public init(
        term: String,
        source: HotwordLearningSource,
        confidence: Double,
        reason: String,
        sourceTerm: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil
    ) {
        self.term = term
        self.source = source
        self.confidence = confidence
        self.reason = reason
        self.sourceTerm = sourceTerm
        self.appName = appName
        self.windowTitle = windowTitle
    }

    public func withContext(appName: String?, windowTitle: String?) -> HotwordCandidateProposal {
        HotwordCandidateProposal(
            term: term,
            source: source,
            confidence: confidence,
            reason: reason,
            sourceTerm: sourceTerm,
            appName: self.appName ?? appName,
            windowTitle: self.windowTitle ?? windowTitle)
    }
}
