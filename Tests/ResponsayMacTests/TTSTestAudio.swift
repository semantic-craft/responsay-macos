import Foundation

/// Shared audio fixtures for cloud-TTS tests (issue 195/197) — one home for the
/// PCM16/WAV encoders so the format detail (little-endian, ×32767) lives in one place.
enum TTSTestAudio {
    /// Float samples → base64-encoded signed 16-bit little-endian PCM.
    static func pcm16Base64(_ samples: [Float]) -> String {
        var pcm = Data()
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            pcm.append(UInt8(truncatingIfNeeded: v))
            pcm.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        return pcm.base64EncodedString()
    }

    /// Float samples → a canonical 16-bit mono PCM WAV container.
    static func wav(_ samples: [Float], sampleRate: Int = 24_000) -> Data {
        var pcm = Data()
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            pcm.append(UInt8(truncatingIfNeeded: v))
            pcm.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        func le32(_ n: Int) -> [UInt8] { [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: n >> $0) } }
        func le16(_ n: Int) -> [UInt8] { [0, 8].map { UInt8(truncatingIfNeeded: n >> $0) } }
        var d = Data("RIFF".utf8); d.append(contentsOf: le32(36 + pcm.count)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); d.append(contentsOf: le32(16)); d.append(contentsOf: le16(1))
        d.append(contentsOf: le16(1)); d.append(contentsOf: le32(sampleRate))
        d.append(contentsOf: le32(sampleRate * 2)); d.append(contentsOf: le16(2)); d.append(contentsOf: le16(16))
        d.append(Data("data".utf8)); d.append(contentsOf: le32(pcm.count)); d.append(pcm)
        return d
    }
}
