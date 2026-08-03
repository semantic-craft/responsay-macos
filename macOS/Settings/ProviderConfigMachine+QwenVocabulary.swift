import Foundation
import ResponsayCore

extension ProviderConfigMachine {
    var qwenVocabularyValidationMessage: String? {
        guard isQwenASRFlash else { return nil }
        let identifier = precompiledVocabularyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }
        guard QwenASRHotwords.normalizedVocabularyIdentifier(identifier) != nil else {
            return "格式不正确；请粘贴百炼生成的 vocab-… ID。无效值不会参与听写。"
        }
        guard let precompiledVocabularyBinding,
              precompiledVocabularyBinding.resolvedIdentifier(
                  model: model,
                  endpoint: qwenRunTaskEndpoint,
                  vocabularyFingerprint: qwenVocabularyFingerprint) != nil else {
            return "当前模型、接入点、Workspace 或识别词典已变化；确认远端词表更新后请点“标记已同步”。"
        }
        return nil
    }

    var qwenVocabularyHelp: String {
        if region == .singapore, !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "用于长期维护的术语。新加坡子 Workspace 按官方限制不支持热词；最近学习和当次临时词仍自动走即时词典。"
        }
        return "用于长期维护的术语；最近学习和当次临时词仍立即生效。官方同次只生效一种，应用会自动选择。"
    }

    /// An ID edit is an explicit assertion that the current local recognition dictionary has been
    /// synchronized to that remote list. Later model/region/workspace/dictionary changes never
    /// silently retarget it; the resolver falls back to instant vocabulary until reconfirmed.
    func writeQwenPrecompiledVocabulary() {
        guard isQwenASRFlash else { return }
        let identifier = precompiledVocabularyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            QwenPrecompiledVocabularySettings.clear(defaults: defaults)
            precompiledVocabularyBinding = nil
            return
        }
        precompiledVocabularyBinding = QwenPrecompiledVocabularySettings.save(
            identifier: identifier,
            model: model,
            endpoint: qwenRunTaskEndpoint,
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
    }

    func markQwenVocabularySynchronized() {
        writeQwenPrecompiledVocabulary()
    }

    func loadQwenPrecompiledVocabulary() {
        guard isQwenASRFlash else {
            precompiledVocabularyBinding = nil
            precompiledVocabularyID = ""
            return
        }
        precompiledVocabularyBinding = QwenPrecompiledVocabularySettings.binding(defaults: defaults)
        precompiledVocabularyID = precompiledVocabularyBinding?.identifier ?? ""
    }

    private var qwenRunTaskEndpoint: QwenRunTaskEndpoint {
        QwenASRFlashRouting.endpoint(workspaceID: workspaceID, region: region)
    }

    private var qwenVocabularyFingerprint: String {
        QwenPrecompiledVocabularySettings.fingerprint(
            terms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            model: model)
    }
}
