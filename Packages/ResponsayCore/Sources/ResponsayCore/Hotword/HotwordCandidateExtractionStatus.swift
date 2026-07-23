import Foundation

public enum HotwordCandidateExtractionStatus: Sendable, Equatable {
    case ready
    case notConfigured
    case malformedResponse
    case lowConfidence
    case timedOut
    case failed(String)
}
