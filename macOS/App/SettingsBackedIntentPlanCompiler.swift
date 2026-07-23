import Foundation
import OSLog
import ResponsayCore

/// Settings-backed Intent-aware plan compiler (#558). App-direct only: resolves the BYOK
/// 「模型与密钥」LLM card at call time and hands the compile to `DirectIntentPlanAPI`.
/// No endpoint → throws, which the pipeline surfaces as `safe-unavailable` — unlike polish
/// there is NO verbatim passthrough here (spec decision 22: enhancement failure never treats
/// the unchecked raw transcript as safe).
///
/// Privacy: logs carry descriptors only (model + error category) — never the transcript,
/// plan, or provider response (spec decision 29; #558 acceptance).
struct SettingsBackedIntentPlanCompiler: IntentPlanCompiler {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "intent")

    /// Injectable for tests; defaults to the real BYOK cloud resolution (thinking off, 435).
    var resolveEndpoint: @Sendable () -> LLMEndpoint? = { LLMEndpointResolver.resolveText() }

    func compile(_ input: IntentCompilerInput) async throws -> Data {
        guard let endpoint = resolveEndpoint() else {
            Diag.llm(.info, "intent compile unavailable — no LLM configured")
            throw LLMEndpointResolver.notConfigured
        }
        // #572: providers measured unable to hold the strict plan contract stop at the
        // capability gate (#548) — the capsule says "换个模型" (not retryable) instead of a
        // retryable "未通过校验" that sends the user in circles. Real-Mac evidence
        // 2026-07-13: mimo returned unverifiable plans on inputs the gold corpus passes.
        if Self.isUnsupportedPlanProvider(endpoint) {
            Self.log.error(
                "intent compile blocked (model \(endpoint.model, privacy: .public)) → capability-unsupported")
            throw IntentCompilerFailure(.capabilityUnsupported)
        }
        Diag.llm(.info, "intent compile start", fields: ["model": endpoint.model, "units": "\(input.sourceUnits.count)"])
        do {
            let data = try await DirectIntentPlanAPI(endpoint: endpoint).compile(input)
            Diag.llm(.info, "intent compile done", fields: ["model": endpoint.model])
            return data
        } catch {
            let category = Self.errorCategory(error)
            Diag.llm(
                .error, "intent compile failed",
                fields: ["model": endpoint.model], error: category)
            Self.log.error(
                "intent compile failed (model \(endpoint.model, privacy: .public)) → safe-unavailable: \(category, privacy: .public)")
            throw error
        }
    }

    /// #572: the strict-plan blocklist — currently EMPTY. mimo was seeded here from real-Mac
    /// evidence (0/12 usable on the shipped prompt), then un-gated after #575's prompt v6 +
    /// verifier normalization measured 96% auto-insert, zero wrong-text over live soaks.
    /// Widen or narrow ONLY against live eval numbers (IntentPromptLiveEvalTests), never by feel.
    static let unsupportedPlanProviders: Set<String> = []

    static func isUnsupportedPlanProvider(_ endpoint: LLMEndpoint) -> Bool {
        unsupportedPlanProviders.contains(endpoint.providerId.lowercased())
    }

    /// Descriptor-only diagnostic category. Never include provider response text, request
    /// content, endpoint details, or a localized error that may embed any of those values.
    private static func errorCategory(_ error: any Error) -> String {
        guard let error = error as? LLMError else {
            return error is CancellationError ? "cancelled" : "unknown"
        }
        switch error {
        case .notConfigured: return "not-configured"
        case .invalidEndpoint: return "invalid-endpoint"
        case .network: return "network"
        case .http(let status, _): return "http-\(status)"
        case .emptyContent: return "empty-content"
        case .badJSON: return "bad-json"
        case .invalidConfiguration: return "invalid-configuration"
        }
    }
}
