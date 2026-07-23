import Foundation

extension IntentUnavailableReason {
    /// Map an error thrown by an `IntentPlanCompiler` to the capsule-facing reason. Pure and
    /// content-free: it inspects the error's *type*, never a provider message string, so no
    /// request or response text can leak into the surfaced category (#559).
    ///
    /// - `IntentCompilerFailure` wins — a compiler that classified its own fault (capability,
    ///   timeout, …) is trusted over the generic transport mapping.
    /// - `CancellationError` → `.cancelled`.
    /// - `LLMError` maps by kind: missing key/endpoint/config → `.compilerUnavailable` (无 Key);
    ///   network/HTTP → `.compilerFailed` (不可达); empty/bad JSON → `.invalidPlan` (坏响应).
    ///   The transport folds `URLError.timedOut` into `.network(String)`, so timeout is NOT
    ///   split out here — that would be fabricating a distinction the string can't prove.
    /// - Anything else → `.compilerFailed` (a safe, non-inserting default).
    static func classify(compilerError error: any Error) -> IntentUnavailableReason {
        if error is CancellationError { return .cancelled }
        if let failure = error as? IntentCompilerFailure { return failure.reason }
        guard let llm = error as? LLMError else { return .compilerFailed }
        switch llm {
        case .notConfigured, .invalidEndpoint, .invalidConfiguration:
            return .compilerUnavailable
        case .network, .http:
            return .compilerFailed
        case .emptyContent, .badJSON:
            return .invalidPlan
        }
    }
}
