import Foundation

public struct HotwordCandidateExtractionResult: Sendable, Equatable {
    public let candidates: [HotwordCandidateProposal]
    public let status: HotwordCandidateExtractionStatus

    public init(candidates: [HotwordCandidateProposal], status: HotwordCandidateExtractionStatus) {
        self.candidates = candidates
        self.status = status
    }
}
