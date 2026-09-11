import ResponsayCore

/// The upstream iterator keeps running while the UI awaits a playback anchor.
/// Cancelling this task therefore reaches the provider even outside iterator.next().
/// Qwen's existing onTermination handlers propagate cancellation to its socket task.
struct ReadAloudStreamSubscription: Sendable {
    let chunks: AsyncThrowingStream<SynthesizedSpeech, Error>
    private let producer: Task<Void, Never>

    init(streamer: any StreamingSpeechSynthesizer, text: String, speed: Double) {
        let (chunks, continuation) = AsyncThrowingStream<SynthesizedSpeech, Error>.makeStream()
        self.chunks = chunks
        producer = Task {
            do {
                try Task.checkCancellation()
                for try await chunk in streamer.stream(text, speed: speed) {
                    try Task.checkCancellation()
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func cancel() { producer.cancel() }
}
