import Foundation

/// Pure decision for the 483 config-change recovery: re-schedule only when engine-path
/// audio was live and a composed utterance is retained (streaming / emergency / idle
/// cannot be re-scheduled). Side-effect-free so it's unit-testable without audio.
enum ReadAloudConfigChange {
    static func shouldReplay(wasActive: Bool, hasUtterance: Bool) -> Bool {
        wasActive && hasUtterance
    }
}
