import Foundation

public struct CaptureResult: Codable, Sendable {
    public let mode: CaptureMode
    public let sourceTranscript: String
    public let insertText: String?
    public let outputLanguage: CaptureOutputLanguage
    public let transformKind: TransformKind
    public let insertPolicy: InsertPolicy
    public let sidecarPolicy: SidecarPolicy
    public let coachCard: ExpressionResult?
    public let intentInsertRoute: IntentInsertRoute?

    public init(
        mode: CaptureMode,
        sourceTranscript: String,
        insertText: String?,
        outputLanguage: CaptureOutputLanguage,
        transformKind: TransformKind,
        insertPolicy: InsertPolicy,
        sidecarPolicy: SidecarPolicy,
        coachCard: ExpressionResult? = nil,
        intentInsertRoute: IntentInsertRoute? = nil
    ) {
        self.mode = mode
        self.sourceTranscript = sourceTranscript
        self.insertText = insertText
        self.outputLanguage = outputLanguage
        self.transformKind = transformKind
        self.insertPolicy = insertPolicy
        self.sidecarPolicy = sidecarPolicy
        self.coachCard = coachCard
        self.intentInsertRoute = intentInsertRoute
    }

    public func validate() throws {
        if mode == .intentAwareDictation, intentInsertRoute == nil {
            throw CaptureResultValidationError.missingIntentInsertRoute
        }
        switch insertPolicy {
        case .insertImmediately, .replaceSelection:
            let text = insertText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if text?.isEmpty != false {
                throw CaptureResultValidationError.missingInsertText(mode: mode)
            }
        case .copyOnly, .noInsert:
            break
        }
    }
}
