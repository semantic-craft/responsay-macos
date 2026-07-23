import Foundation

public protocol TranscriptionAPI: Sendable {
    func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult
}

public protocol StreamingTranscriptionAPI: TranscriptionAPI {
    /// Streams text deltas for a completed audio upload. This is not necessarily
    /// realtime microphone recognition; providers such as MiMo first receive the
    /// whole audio clip, then stream `delta` text while producing the final ASR.
    func streamTranscription(audio: Data, mimeType: String, language: String) -> AsyncThrowingStream<TextStreamEvent, Error>
}
