import Foundation

public protocol HotwordCandidateExtracting: Sendable {
    func extract(_ context: HotwordCorrectionContext) async throws -> [HotwordCandidateProposal]
}
