import Foundation

public struct CaptureRequest: Codable, Sendable, Equatable {
    public let mode: CaptureMode
    public let sourceTranscript: String?
    public let selectedText: String?
    public let sourceLanguage: String?
    public let targetLanguage: String?
    public let sidecarOverride: SidecarPolicy?

    public init(
        mode: CaptureMode,
        sourceTranscript: String? = nil,
        selectedText: String? = nil,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        sidecarOverride: SidecarPolicy? = nil
    ) {
        self.mode = mode
        self.sourceTranscript = sourceTranscript
        self.selectedText = selectedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sidecarOverride = sidecarOverride
    }
}
