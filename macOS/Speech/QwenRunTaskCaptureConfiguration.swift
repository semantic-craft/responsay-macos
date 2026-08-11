import Foundation
import ResponsayCore
import ResponsaySpeech

/// Resolves one immutable Qwen run-task configuration at capture start. The router owns when this
/// is called; the value keeps endpoint, model, credential, Context, and vocabulary from mixing with
/// settings changes made during an active capture.
enum QwenRunTaskCaptureConfiguration {
    static func resolve(
        defaults: UserDefaults = .standard,
        context: [String] = [],
        contextScope: String? = nil,
        requestHotwords: [String]? = nil,
        keyReader: @escaping ASRKeyReader = { BYOKKeychain.read($0) }
    ) -> QwenRunTaskCaptureConfig {
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.asr, providerId: QwenASRFlashRouting.providerId)
        let endpoint = QwenASRFlashRouting.endpoint(
            workspaceID: effective.workspaceID,
            region: effective.region)
        let persistentHotwords = ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults)
        let requestHotwords = requestHotwords
            ?? ContextHotwordSettings.asrWeakPrompt(defaults: defaults)
        let fingerprint = QwenPrecompiledVocabularySettings.fingerprint(
            terms: persistentHotwords,
            model: effective.model)
        let resolvedIdentifier = QwenPrecompiledVocabularySettings.binding(defaults: defaults)?
            .resolvedIdentifier(
                model: effective.model,
                endpoint: endpoint,
                vocabularyFingerprint: fingerprint)
        let persistentVocabulary = QwenASRHotwords.vocabulary(
            from: persistentHotwords,
            model: effective.model)
        let requestVocabulary = QwenASRHotwords.vocabulary(
            from: requestHotwords,
            model: effective.model)
        let shouldUsePrecompiled = endpoint.supportsHotwords
            && resolvedIdentifier != nil
            && requestVocabulary == persistentVocabulary

        let effectiveInstantHotwords = requestVocabulary.keys.sorted()
        let effectivePersistentHotwords = persistentVocabulary.keys.sorted()
        return QwenRunTaskCaptureConfig(
            endpoint: endpoint,
            apiKey: effective.apiKey ?? "",
            model: effective.model,
            hotwords: endpoint.supportsHotwords && !shouldUsePrecompiled
                ? effectiveInstantHotwords
                : [],
            effectiveEchoTerms: effectiveEchoTerms(
                endpointSupportsHotwords: endpoint.supportsHotwords,
                shouldUsePrecompiled: shouldUsePrecompiled,
                instant: effectiveInstantHotwords,
                persistent: effectivePersistentHotwords),
            precompiledVocabularyID: shouldUsePrecompiled ? resolvedIdentifier : nil,
            context: context,
            contextScope: contextScope,
            heartbeat: true)
    }

    /// Adds the bounded screen harvest to an already immutable endpoint/model/key/dictionary
    /// snapshot. A precompiled ID is retained when the harvest contributes no valid new term;
    /// otherwise the request switches to the complete instant vocabulary for this capture.
    static func augment(
        _ base: QwenRunTaskCaptureConfig,
        transientTerms: [String]
    ) -> QwenRunTaskCaptureConfig {
        var config = base
        guard config.endpoint.supportsHotwords else {
            config.hotwords = []
            config.effectiveEchoTerms = []
            config.precompiledVocabularyID = nil
            return config
        }
        let combined = config.effectiveEchoTerms + transientTerms
        let filtered = QwenASRHotwords.vocabulary(from: combined, model: config.model).keys.sorted()
        let addsTransientVocabulary = !Set(filtered).isSubset(of: Set(config.effectiveEchoTerms))
        if config.precompiledVocabularyID != nil, addsTransientVocabulary {
            config.precompiledVocabularyID = nil
            config.hotwords = filtered
        } else if config.precompiledVocabularyID == nil {
            config.hotwords = filtered
        }
        config.effectiveEchoTerms = config.precompiledVocabularyID == nil
            ? filtered
            : base.effectiveEchoTerms
        return config
    }

    private static func effectiveEchoTerms(
        endpointSupportsHotwords: Bool,
        shouldUsePrecompiled: Bool,
        instant: [String],
        persistent: [String]
    ) -> [String] {
        guard endpointSupportsHotwords else { return [] }
        return shouldUsePrecompiled ? persistent : instant
    }
}
