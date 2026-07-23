import Foundation

public struct ResolvedCaptureMode: Codable, Sendable, Equatable {
    public let mode: CaptureMode
    public let transformKind: TransformKind
    public let outputLanguage: CaptureOutputLanguage
    public let sidecarPolicy: SidecarPolicy
    public let insertPolicy: InsertPolicy

    public init(
        mode: CaptureMode,
        transformKind: TransformKind,
        outputLanguage: CaptureOutputLanguage,
        sidecarPolicy: SidecarPolicy,
        insertPolicy: InsertPolicy
    ) {
        self.mode = mode
        self.transformKind = transformKind
        self.outputLanguage = outputLanguage
        self.sidecarPolicy = sidecarPolicy
        self.insertPolicy = insertPolicy
    }
}
