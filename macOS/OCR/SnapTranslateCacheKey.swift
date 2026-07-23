import ResponsayCore

struct SnapTranslateCacheKey: Hashable {
    let serviceID: String
    let mode: OCRLayoutMode
    let target: TranslationTargetLanguage
    let revision: Int

    init(
        serviceID: String,
        mode: OCRLayoutMode,
        target: TranslationTargetLanguage,
        revision: Int
    ) {
        self.serviceID = serviceID
        self.mode = mode
        self.target = target
        self.revision = revision
    }
}
