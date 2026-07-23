import Foundation

/// A word (or sub-token) with its playback window, for word highlight + seek
/// (spec §1.2.2). `confidence` is provider-supplied when available.
public struct TimedWord: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var confidence: Double?

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
