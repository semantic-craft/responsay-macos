import Foundation

/// A transcript update derived from a realtime ASR event stream. Extracted
/// from the retired `QwenTranscriptAssembler` (issue 289) — the assembler died
/// with the Qwen realtime engine, while provider clients fold
/// its task-protocol events into the same update shape.
public enum TranscriptUpdate: Sendable, Equatable {
    /// Live preview of the in-progress utterance (`text + stash`).
    case partial(preview: String)
    /// Confirmed final transcript for the utterance.
    case final(transcript: String)
    /// Recognition failed; `message` is the service-provided reason when available.
    case failed(message: String?)
}
