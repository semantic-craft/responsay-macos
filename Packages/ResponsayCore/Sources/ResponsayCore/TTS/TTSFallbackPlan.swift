import Foundation

/// Which on-device TTS to use when resolving the read-aloud voice (#391, spec §6).
public enum TTSFallbackTarget: Equatable, Sendable {
    /// The user's selected engine (a cloud engine with a key, or installed Kokoro).
    case selected
    /// On-device Kokoro (already downloaded) — the preferred fallback.
    case kokoro
    /// Apple's system synthesizer — the guaranteed, zero-download last resort.
    case system
}

/// Pure decision for the always-usable TTS chain (spec §6): the selected engine if
/// it's ready, else Kokoro if it's installed, else the system synthesizer. Kept
/// side-effect-free so the chain is unit-testable without audio or models.
public enum TTSFallbackPlan {
    public static func target(selectedReady: Bool, kokoroInstalled: Bool) -> TTSFallbackTarget {
        if selectedReady { return .selected }
        if kokoroInstalled { return .kokoro }
        return .system
    }

    public static func runtimeTargets(selectedIsKokoro: Bool) -> [TTSFallbackTarget] {
        selectedIsKokoro ? [.kokoro, .system] : [.selected, .kokoro, .system]
    }
}
