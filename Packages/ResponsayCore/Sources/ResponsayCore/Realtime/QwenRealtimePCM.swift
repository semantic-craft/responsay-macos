import Foundation

/// Converts 16 kHz mono Float32 mic samples to the 16-bit little-endian PCM the
/// qwen3-asr-flash-realtime `input_audio_buffer.append` expects. Pure so it can be
/// unit-tested; the mic-buffer extraction + socket push live in the capture service.
public enum QwenRealtimePCM {
    public static func int16LE(from floats: [Float]) -> Data {
        var data = Data(capacity: floats.count * 2)
        for float in floats {
            let clamped = max(-1, min(1, float))
            var sample = Int16(clamped * 32767).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return data
    }
}
