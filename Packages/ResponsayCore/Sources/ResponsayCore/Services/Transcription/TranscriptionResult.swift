import Foundation

public struct TranscriptionResult: Decodable, Sendable, Equatable {
    public let text: String
    public let model: String?
    public let language: String?
    public let provider: String?
}
