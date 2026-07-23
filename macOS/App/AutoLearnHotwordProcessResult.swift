import Foundation
import ResponsayCore

struct AutoLearnHotwordProcessResult: Equatable {
    /// Every term added to the auto dictionary this round (specialized + ordinary).
    let addedTerms: [String]
    /// The subset of `addedTerms` that should surface the undo toast — specialized terms only.
    /// Ordinary terms are added silently (PRD 2026-06-19 §3, Tier 2). Defaults empty.
    var notifiedTerms: [String] = []
    let extractionStatus: HotwordCandidateExtractionStatus
}
