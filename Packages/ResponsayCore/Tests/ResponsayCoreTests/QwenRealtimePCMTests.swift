import Foundation
import Testing
@testable import ResponsayCore

/// The live capture path converts each 16 kHz mono Float32 mic buffer to 16-bit
/// little-endian PCM before `input_audio_buffer.append`. This pins the conversion
/// (the mic tap + socket drive around it are the HITL boundary).
@Suite("QwenRealtimePCM")
struct QwenRealtimePCMTests {

    @Test func int16LEClampsAndPacksLittleEndian() {
        let data = QwenRealtimePCM.int16LE(from: [0.0, 1.0, -1.0, 2.0, -2.0])
        var expected = Data()
        for sample: Int16 in [0, 32767, -32767, 32767, -32767] {   // ±2.0 clamped to ±1.0
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { expected.append(contentsOf: $0) }
        }
        #expect(data == expected)
    }

    @Test func emptyProducesEmpty() {
        #expect(QwenRealtimePCM.int16LE(from: []) == Data())
    }
}
