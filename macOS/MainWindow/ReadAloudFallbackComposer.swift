import OSLog
import ResponsayCore

/// The composed audio plus which provider produced it (497) — `isFallback` is true when a
/// non-selected provider was used, so the UI can tell the user the voice changed.
struct ReadAloudComposeOutcome {
    let audio: ComposedReadAloud
    let providerTitle: String
    let isFallback: Bool
}

struct ReadAloudFallbackComposer {
    private let composer: ReadAloudComposer
    private let attempts: [TTSFallbackAttempt]
    private let speed: Double
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloud")

    init(composer: ReadAloudComposer, attempts: [TTSFallbackAttempt], speed: Double) {
        self.composer = composer
        self.attempts = attempts
        self.speed = speed
    }

    @MainActor
    func compose(
        _ text: String,
        modeName: String,
        diag: ReadAloudDiagnosticContext,
        cache: ReadAloudComposeCache? = nil,
        cacheKey: String? = nil
    ) async -> ReadAloudComposeOutcome? {
        // 495: a cache hit skips synthesis entirely (Coach standard sentences only —
        // Ask Anything passes no key). Only attempt-0 output is cached, so a hit is never
        // a fallback.
        if let cache, let cacheKey, let hit = cache.get(cacheKey) {
            Diag.tts(.info, "compose cache hit", fields: diag.fields(
                mode: modeName, phase: "synth", attempt: 0,
                provider: "cache", fallback: "none", result: "cacheHit",
                extra: ["cacheKeyHash": String(cacheKey.hashValue)]))
            return ReadAloudComposeOutcome(
                audio: hit, providerTitle: attempts.first?.title ?? "cache", isFallback: false)
        }
        for (index, attempt) in attempts.enumerated() {
            guard !Task.isCancelled else { return nil }
            let attemptNumber = index + 1
            let fallbackTo = attempts.dropFirst(attemptNumber).first?.title ?? "none"
            do {
                let synth = try attempt.makeSynthesizer()
                let composer = self.composer
                let rate = speed
                let composed = try await Task.detached(priority: .userInitiated) {
                    try await composer.compose(text, using: synth, speed: rate)
                }.value
                guard composed.hasPlayableAudio, !composed.timeline.isEmpty else {
                    throw TTSError.providerReturnedNoAudio(provider: attempt.title)
                }
                // 485: PCM-validity observability — frame count + peak level confirm the
                // chunks carry real (non-silent, finite) audio.
                let totalFrames = composed.chunks.reduce(0) { $0 + $1.samples.count }
                let peakAbs = composed.chunks.lazy.flatMap(\.samples).map(abs).max() ?? 0
                Diag.tts(.info, "synth attempt done", fields: diag.fields(
                    mode: modeName, phase: "synth", attempt: attemptNumber,
                    provider: attempt.title, fallback: fallbackTo, result: "success",
                    extra: [
                        "durationMs": String(Int(composed.totalDuration * 1000)),
                        "chunks": String(composed.chunks.count),
                        "totalFrames": String(totalFrames),
                        "peakAbs": String(format: "%.3f", peakAbs),
                    ]))
                Self.log.notice(
                    "compose done attempt=\(attemptNumber, privacy: .public) provider=\(attempt.title, privacy: .public) chunks=\(composed.chunks.count, privacy: .public) durationMs=\(Int(composed.totalDuration * 1000), privacy: .public) timeline=\(composed.timeline.count, privacy: .public)"
                )
                // 495: only cache the selected engine's own output (index 0). Caching a
                // fallback result under the selected-config key would replay stale audio
                // once the selected engine recovers.
                if index == 0, let cache, let cacheKey { cache.set(cacheKey, composed) }
                return ReadAloudComposeOutcome(
                    audio: composed, providerTitle: attempt.title, isFallback: index > 0)
            } catch {
                let code = ReadAloudDiagnostics.errorCode(error)
                let title = fallbackTo == "none" ? "synth failed" : "synth attempt failed"
                Diag.tts(.error, title, fields: diag.fields(
                    mode: modeName, phase: "synth", attempt: attemptNumber,
                    provider: attempt.title, fallback: fallbackTo, result: "failed",
                    extra: ["errorCode": code]), error: code)
                Self.log.info(
                    "tts attempt failed attempt=\(attemptNumber, privacy: .public) provider=\(attempt.title, privacy: .public) error=\(code, privacy: .public) fallbackTo=\(fallbackTo, privacy: .public)"
                )
            }
        }
        return nil
    }
}
