import Foundation

/// What an ASR engine can do, declared explicitly instead of inferred from optional-protocol
/// conformance + `as?` casts at the router. Lets `RoutedSpeechCaptureService` dispatch the post-ASR
/// pipeline (and, later, partials / profile) per engine rather than running every step on every
/// engine. The default is the on-device / final-only posture; cloud and realtime adapters override.
public struct SpeechCaptureCapability: Sendable, Equatable {
    /// How the engine emits live preview text while recording.
    public enum PartialStyle: Sendable, Equatable {
        /// Final-only: no live partials (offline sherpa, Apple, Volcengine).
        case none
        /// Cosmetic partials trickled from post-upload SSE; insertion still waits for `stop()`.
        case postUploadSSE
        /// True frame-by-frame live partials (for example, 千问极速实时).
        case realtimeFrameByFrame
    }

    public var partialStyle: PartialStyle
    /// The request incorporates the `SpeechCaptureProfile` (faithful vs dictation).
    public var profileAware: Bool
    /// The engine injects the weak biasing hint **as text**, so a near-empty clip can echo the list
    /// back verbatim (`HotwordEchoFilter` defends this). On-device engines send no such hint and must
    /// NOT run the echo filter, or a legitimate term-list dictation ("Westlaw, SSRN") is mis-dropped.
    public var needsEchoFilter: Bool

    public init(
        partialStyle: PartialStyle = .none,
        profileAware: Bool = false,
        needsEchoFilter: Bool = false
    ) {
        self.partialStyle = partialStyle
        self.profileAware = profileAware
        self.needsEchoFilter = needsEchoFilter
    }
}
