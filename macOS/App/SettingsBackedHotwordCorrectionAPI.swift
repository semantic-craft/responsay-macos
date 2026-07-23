import Foundation
import OSLog
import ResponsayCore

/// Settings-backed gate for the optional BYOK-LLM hotword-correction tier (#500 S3). Off by default;
/// when on, it retrieves the near-miss term candidates and runs one correction pass against the
/// resolved cloud BYOK text model. An exact, zero-cost no-op when
/// the tier is off, no usable model is configured, or nothing is near-miss — so the default dictation
/// path is completely unchanged.
struct SettingsBackedHotwordCorrectionAPI {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "hotword-correction")

    var isEnabled: @Sendable () -> Bool = { HotwordLLMCorrectionSettings.isEnabled() }
    var resolveEndpoint: @Sendable () -> LLMEndpoint? = { LLMEndpointResolver.resolveText() }

    /// Returns the transcript with near-miss hotword spellings sharpened, or the input unchanged.
    /// `userTerms` should be the user-provenance hard-match terms (#470) — seeds are not corrected.
    func correct(_ transcript: String, userTerms: [String]) async -> String {
        guard isEnabled() else { return transcript }
        guard let endpoint = resolveEndpoint() else { return transcript }
        let candidates = HotwordCorrectionCandidates.nearMiss(in: transcript, userTerms: userTerms)
        guard !candidates.isEmpty else { return transcript }
        log.info("hotword LLM correction: \(candidates.count, privacy: .public) candidate(s), model \(endpoint.model, privacy: .public)")
        return await DirectHotwordCorrectionAPI(endpoint: endpoint).correct(transcript, candidates: candidates)
    }
}
