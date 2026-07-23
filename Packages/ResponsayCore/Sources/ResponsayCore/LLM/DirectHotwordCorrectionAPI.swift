import Foundation

/// The optional BYOK-LLM correction tier's LLM call (#500 S3). Given a transcript and the retrieved
/// near-miss term candidates, it asks the BYOK provider to repair only those terms, then runs the
/// reply through the divergence guard. **Advisory, never authoritative**: any failure, empty
/// candidate list, or untrusted reply returns the input unchanged — it can only ever sharpen the
/// hard-matched transcript, never break dictation (ADR-0008). Mirrors `DirectTextPolishAPI`'s seam.
public protocol HotwordCorrectionAPI: Sendable {
    func correct(_ transcript: String, candidates: [String]) async -> String
}

public struct DirectHotwordCorrectionAPI: HotwordCorrectionAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    /// The correction gates the dictation insert, so it must NOT inherit the 60s cloud default — a
    /// slow/hung provider would stall "speak → insert". A few seconds is plenty for a short reply;
    /// past that the advisory tier degrades to the hard-matched text. (review: latency finding)
    private static let requestTimeout: TimeInterval = 6

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func correct(_ transcript: String, candidates: [String]) async -> String {
        guard !candidates.isEmpty else { return transcript }
        let prompt = HotwordCorrectionPromptBuilder.build(transcript: transcript, candidates: candidates)
        do {
            let request = try LLMChatRequestBuilder.makeRequest(
                endpoint: endpoint, system: prompt.system, user: prompt.user,
                responseFormat: LLMResponseFormat.textChanges,
                generationAction: .polish, timeout: Self.requestTimeout)
            let raw = try await client.execute(request)
            // Reuse the polish envelope/plain-text tolerance; fall back to the input if unparseable.
            let corrected = PolishPlainTextFallback.result(fromRaw: raw, input: transcript)?.text ?? transcript
            return HotwordCorrectionGuard.resolved(
                original: transcript, corrected: corrected, candidates: candidates)
        } catch {
            return transcript   // advisory tier — a failure must never break the dictation insert
        }
    }
}
