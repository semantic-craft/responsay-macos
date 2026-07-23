import Foundation
import ResponsayCore

/// Decodes cloud TTS audio payloads into `SynthesizedSpeech` (issue 195). Pure
/// byte math — no AVFoundation, no temp files — so it's deterministic and headless
/// testable. Two shapes cover the surveyed providers:
/// - **WAV container** (OpenAI `/audio/speech` `response_format=wav`, MiMo base64 WAV)
/// - **headerless PCM16 LE** (Qwen DashScope, Gemini `audio/L16;rate=24000`)
enum CloudTTSAudioDecoder {
    enum DecodeError: Error, Equatable { case empty, notWAV, noData }

    /// Signed 16-bit little-endian PCM → mono Float in [-1, 1]. `channels > 1` is
    /// down-mixed by averaging.
    static func pcm16(_ data: Data, sampleRate: Int, channels: Int = 1) throws -> SynthesizedSpeech {
        guard !data.isEmpty else { throw DecodeError.empty }
        let ch = max(1, channels)
        let frameCount = data.count / 2 / ch
        var samples = [Float](repeating: 0, count: frameCount)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for frame in 0..<frameCount {
                var acc: Int32 = 0
                for c in 0..<ch {
                    let i = (frame * ch + c) * 2
                    let lo = Int16(raw[i]); let hi = Int16(raw[i + 1])
                    acc += Int32(Int16(bitPattern: UInt16(bitPattern: lo) | (UInt16(bitPattern: hi) << 8)))
                }
                samples[frame] = Float(acc) / Float(ch) / 32768.0
            }
        }
        return SynthesizedSpeech(samples: samples, sampleRate: sampleRate, providerTiming: nil)
    }

    /// Parse a canonical PCM RIFF/WAVE container (fmt + data chunks). Throws
    /// `.notWAV` if it isn't `RIFF…WAVE`, `.noData` if the `data` chunk is missing.
    static func wav(_ data: Data) throws -> SynthesizedSpeech {
        guard data.count > 44 else { throw DecodeError.empty }
        let bytes = [UInt8](data)
        func tag(_ off: Int) -> String { String(bytes: bytes[off..<off + 4], encoding: .ascii) ?? "" }
        func u32(_ off: Int) -> Int {
            Int(bytes[off]) | Int(bytes[off + 1]) << 8 | Int(bytes[off + 2]) << 16 | Int(bytes[off + 3]) << 24
        }
        func u16(_ off: Int) -> Int { Int(bytes[off]) | Int(bytes[off + 1]) << 8 }
        guard tag(0) == "RIFF", tag(8) == "WAVE" else { throw DecodeError.notWAV }

        var cursor = 12
        var sampleRate = 24_000
        var channels = 1
        var bits = 16
        var pcm: Data?
        while cursor + 8 <= bytes.count {
            let id = tag(cursor)
            let size = u32(cursor + 4)
            let body = cursor + 8
            if id == "fmt " {
                channels = u16(body + 2)
                sampleRate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                let end = min(body + size, bytes.count)
                pcm = data.subdata(in: body..<end)
            }
            cursor = body + size + (size & 1)  // chunks are word-aligned
        }
        guard let pcm else { throw DecodeError.noData }
        guard bits == 16 else {
            // We request 16-bit; anything else is unexpected — fall back to raw count.
            throw DecodeError.notWAV
        }
        return try pcm16(pcm, sampleRate: sampleRate, channels: channels)
    }
}
