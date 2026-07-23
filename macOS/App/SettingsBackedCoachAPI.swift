import Foundation
import ResponsayCore

struct SettingsBackedCoachAPI: CoachAPI {

    func express(
        _ intent: String,
        context: ExpressionContext?,
        target: TranslationTargetLanguage
    ) async throws -> ExpressionResult {
        guard let endpoint = LLMEndpointResolver.resolveText() else { throw LLMEndpointResolver.notConfigured }
        Diag.llm(.info, "express start", fields: ["intentChars": String(intent.count), "target": target.rawValue, "model": endpoint.model])
        do {
            let result = try await DirectCoachAPI(
                endpoint: endpoint,
                register: CoachRegisterSettings.selectedRegister(),
                strategy: ExpressRewriteStrategySettings.selectedStrategy())
                .express(intent, context: context, target: target)
            Diag.llm(.info, "express done", fields: ["target": target.rawValue, "model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "express failed", fields: ["intentChars": String(intent.count), "target": target.rawValue, "model": endpoint.model], error: error.localizedDescription)
            throw error
        }
    }

    func ask(_ question: String, context: String) async throws -> ExpressionResult {
        guard let endpoint = LLMEndpointResolver.resolveText() else { throw LLMEndpointResolver.notConfigured }
        Diag.llm(.info, "ask start", fields: ["questionChars": String(question.count), "model": endpoint.model])
        do {
            let result = try await DirectCoachAPI(
                endpoint: endpoint, register: CoachRegisterSettings.selectedRegister())
                .ask(question, context: context)
            Diag.llm(.info, "ask done", fields: ["model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "ask failed", fields: ["questionChars": String(question.count), "model": endpoint.model], error: error.localizedDescription)
            throw error
        }
    }
}
