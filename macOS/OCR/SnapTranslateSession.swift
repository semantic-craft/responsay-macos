import Foundation
import Observation
import ResponsayCore

@MainActor
@Observable
final class SnapTranslateSession {
    let draft: OCRTextDraft

    private(set) var output = ""
    private(set) var isTranslating = false
    private(set) var errorText: String?

    private var cache: [SnapTranslateCacheKey: String] = [:]
    private var activeRequestID: UUID?
    private var lastDisplayedCacheKey: SnapTranslateCacheKey?

    init(original: OCRResult) {
        draft = OCRTextDraft(result: original)
    }

    func isTranslationStale(
        serviceId: String,
        target: TranslationTargetLanguage
    ) -> Bool {
        !output.isEmpty && lastDisplayedCacheKey != cacheKey(serviceId: serviceId, target: target)
    }

    func hasCachedTranslation(
        serviceId: String,
        target: TranslationTargetLanguage
    ) -> Bool {
        cache[cacheKey(serviceId: serviceId, target: target)] != nil
    }

    func invalidate(serviceId: String, target: TranslationTargetLanguage) {
        cache.removeValue(forKey: cacheKey(serviceId: serviceId, target: target))
    }

    @discardableResult
    func translate(
        serviceId: String,
        target: TranslationTargetLanguage,
        using translator: @MainActor (String, String, TranslationTargetLanguage) async -> Result<String, SnapTranslateError>
    ) async -> String? {
        errorText = nil
        let sourceRevision = draft.revision
        let sourceMode = draft.mode
        let sourceText = draft.text
        let key = cacheKey(serviceId: serviceId, target: target)

        if let cached = cache[key] {
            output = cached
            lastDisplayedCacheKey = key
            return cached
        }
        guard !serviceId.isEmpty else {
            output = ""
            errorText = "没有可用的译文服务，请先在设置里配置文本模型。"
            return nil
        }

        let requestID = UUID()
        activeRequestID = requestID
        isTranslating = true
        let result = await translator(sourceText, serviceId, target)

        guard activeRequestID == requestID else { return nil }
        activeRequestID = nil
        isTranslating = false
        guard draft.revision == sourceRevision, draft.mode == sourceMode else { return nil }

        switch result {
        case let .success(translated):
            cache[key] = translated
            output = translated
            lastDisplayedCacheKey = key
            return translated
        case let .failure(failure):
            errorText = failure.message
            return nil
        }
    }

    private func cacheKey(serviceId: String, target: TranslationTargetLanguage) -> SnapTranslateCacheKey {
        SnapTranslateCacheKey(
            serviceID: serviceId,
            mode: draft.mode,
            target: target,
            revision: draft.revision)
    }
}
