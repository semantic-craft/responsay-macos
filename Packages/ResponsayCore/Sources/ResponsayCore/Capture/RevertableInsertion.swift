import Foundation

/// Revert AI (P0b): the just-inserted dictation result, kept briefly so the user can swap the AI
/// version back to what they actually said. `polished` is the text we inserted; `raw` is the
/// original ASR transcript. Only set for a direct auto-insert where the two differ (so raw-mode and
/// selection-replace never offer a pointless revert).
public struct RevertableInsertion: Sendable, Equatable {
    public let polished: String
    public let raw: String

    public init(polished: String, raw: String) {
        self.polished = polished
        self.raw = raw
    }
}
