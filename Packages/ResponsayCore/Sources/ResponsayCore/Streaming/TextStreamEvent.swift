import Foundation

/// One event from a streamed text-producing operation: an incremental text token,
/// the terminal marker, or an in-band failure. Used by LLM transforms and
/// post-upload streaming ASR providers.
public enum TextStreamEvent: Equatable, Sendable {
    case delta(String)
    case done
    case failed(String)
}
