import AVFoundation
import Foundation
import ResponsayCore

/// Guaranteed on-device TTS fallback (#391, spec §6): wraps Apple's `AVSpeechSynthesizer`
/// so the read-aloud pipeline always has a working voice even when no model is downloaded
/// and no cloud key is configured. System voices, zero download, fully on-device.
///
/// Renders to PCM samples via `write(_:toBufferCallback:)` (no audio device needed), so it
/// plugs into the same `SpeechSynthesizer` abstraction as Kokoro and the cloud engines.
final class SystemSpeechSynthesizer: SpeechSynthesizer {
    /// Serial buffer accumulation — `AVSpeechSynthesizer` invokes the write callback one
    /// buffer at a time, so unchecked Sendable is safe here.
    private final class Accumulator: @unchecked Sendable {
        var samples: [Float] = []
        var sampleRate = 0
        var resumed = false
    }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = Float(Self.clampSpeed(speed)) * AVSpeechUtteranceDefaultSpeechRate

        let synth = AVSpeechSynthesizer()
        let acc = Accumulator()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SynthesizedSpeech, Error>) in
            synth.write(utterance) { [synth] buffer in
                _ = synth  // keep the synthesizer alive until the final callback
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                guard pcm.frameLength > 0 else {
                    // An empty buffer signals completion.
                    guard !acc.resumed else { return }
                    acc.resumed = true
                    if acc.samples.isEmpty {
                        continuation.resume(throwing: TTSError.providerReturnedNoAudio(provider: "Apple"))
                    } else {
                        continuation.resume(
                            returning: SynthesizedSpeech(samples: acc.samples, sampleRate: acc.sampleRate))
                    }
                    return
                }
                acc.sampleRate = Int(pcm.format.sampleRate)
                acc.samples.append(contentsOf: Self.monoFloat(from: pcm))
            }
        }
    }

    private static func monoFloat(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        if let floats = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: floats[0], count: frames))
        }
        if let ints = buffer.int16ChannelData {
            return UnsafeBufferPointer(start: ints[0], count: frames).map { Float($0) / 32_768.0 }
        }
        return []
    }
}
