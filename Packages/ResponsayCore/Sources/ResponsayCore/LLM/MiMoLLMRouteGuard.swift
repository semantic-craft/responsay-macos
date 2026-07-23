import Foundation

enum MiMoLLMRouteGuard {
    static func validate(endpoint: LLMEndpoint) throws {
        guard isMiMo(endpoint) else { return }
        guard let key = endpoint.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !key.isEmpty else { return }

        if isTokenPlanHost(endpoint.host), key.hasPrefix("sk-") {
            throw LLMError.invalidConfiguration("MiMo Token Plan endpoints require a tp- key.")
        }
        if isPayAsYouGoHost(endpoint.host), key.hasPrefix("tp-") {
            throw LLMError.invalidConfiguration("MiMo pay-as-you-go endpoints require an sk- key.")
        }
    }

    private static func isMiMo(_ endpoint: LLMEndpoint) -> Bool {
        endpoint.providerId.lowercased() == "mimo" || endpoint.host.contains("xiaomimimo")
    }

    private static func isTokenPlanHost(_ host: String) -> Bool {
        host.contains("token-plan") && host.contains("xiaomimimo.com")
    }

    private static func isPayAsYouGoHost(_ host: String) -> Bool {
        host == "api.xiaomimimo.com"
    }
}
