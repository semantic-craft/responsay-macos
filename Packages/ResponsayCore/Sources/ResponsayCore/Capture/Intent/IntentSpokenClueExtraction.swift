import Foundation

/// One name assembled from spoken orthographic clues (#562, 口述释字): the canonical value the
/// clues prove, the clue-only source units (which must take the `grounding` role and never
/// render), and — when exactly one span qualifies — the transcript span the value replaces.
/// `target == nil` means the referent is ambiguous or absent; the compiler must then abstain
/// into needs-review instead of guessing.
public struct IntentSpokenClueExtraction: Sendable, Equatable {
    public let value: String
    public let clueSourceIDs: [String]
    public let target: IntentPlanSourceReference?

    public init(value: String, clueSourceIDs: [String], target: IntentPlanSourceReference?) {
        self.value = value
        self.clueSourceIDs = clueSourceIDs
        self.target = target
    }
}
