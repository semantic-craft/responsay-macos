import CryptoKit
import Foundation
import ResponsayCore

/// Local binding for the user's durable Qwen vocabulary. Only the opaque provider ID, environment
/// metadata and a one-way dictionary fingerprint are persisted; vocabulary contents stay in the
/// existing private dictionary stores and never enter diagnostics.
enum QwenPrecompiledVocabularySettings {
    static let suffix = "precompiledVocabularyBinding"
    static let providerID = QwenASRFlashRouting.providerId
    static var scopedDefaultsKey: String {
        CapabilityProviderConfigStore.scopedKey(suffix, providerId: providerID, capability: .asr)
    }

    static func binding(defaults: UserDefaults = .standard) -> QwenPrecompiledVocabularyBinding? {
        guard let raw = CapabilityProviderConfigStore.string(
            suffix,
            providerId: providerID,
            capability: .asr,
            defaults: defaults,
            activeProviderId: defaults.string(forKey: CapabilityProviderConfigStore.activeKey(
                "provider", capability: .asr))),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(QwenPrecompiledVocabularyBinding.self, from: data)
    }

    @discardableResult
    static func save(
        identifier: String,
        model: String,
        endpoint: QwenRunTaskEndpoint,
        vocabularyTerms: [String],
        defaults: UserDefaults = .standard
    ) -> QwenPrecompiledVocabularyBinding? {
        guard let identifier = QwenASRHotwords.normalizedVocabularyIdentifier(identifier) else {
            clear(defaults: defaults)
            return nil
        }
        let rawWorkspace = endpoint.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedWorkspace = QwenRunTaskEndpoint.normalizedWorkspaceID(rawWorkspace)
        guard endpoint.supportsHotwords,
              rawWorkspace.isEmpty || normalizedWorkspace != nil else {
            clear(defaults: defaults)
            return nil
        }
        let binding = QwenPrecompiledVocabularyBinding(
            identifier: identifier,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            region: endpoint.region,
            workspaceID: normalizedWorkspace,
            vocabularyFingerprint: fingerprint(terms: vocabularyTerms, model: model))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(binding),
              let raw = String(data: data, encoding: .utf8) else {
            clear(defaults: defaults)
            return nil
        }
        CapabilityProviderConfigStore.set(
            raw,
            suffix: suffix,
            providerId: providerID,
            capability: .asr,
            defaults: defaults,
            activeProviderId: defaults.string(forKey: CapabilityProviderConfigStore.activeKey(
                "provider", capability: .asr)))
        return binding
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: scopedDefaultsKey)
        let activeProvider = defaults.string(forKey: CapabilityProviderConfigStore.activeKey(
            "provider", capability: .asr))
        if CapabilitySelectionSync.providerMatches(activeProvider, providerID, capability: .asr) {
            defaults.removeObject(forKey: CapabilityProviderConfigStore.activeKey(suffix, capability: .asr))
        }
    }

    static func fingerprint(terms: [String], model: String) -> String {
        let normalized = QwenASRHotwords.vocabulary(from: terms, model: model).keys.sorted()
        let data = Data(normalized.joined(separator: "\u{1F}").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
