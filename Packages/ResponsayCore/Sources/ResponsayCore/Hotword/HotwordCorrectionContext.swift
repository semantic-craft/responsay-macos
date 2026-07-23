import Foundation

public struct HotwordCorrectionContext: Sendable, Equatable, Codable {
    public let insertedText: String
    public let userFinalText: String
    public let appName: String?
    public let windowTitle: String?

    public init(insertedText: String, userFinalText: String, appName: String?, windowTitle: String?) {
        self.insertedText = insertedText
        self.userFinalText = userFinalText
        self.appName = appName
        self.windowTitle = windowTitle
    }
}
