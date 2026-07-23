import Foundation
import Testing
@testable import ResponsayCore

/// The capture layer hands `transcribe(audio:)` a 16 kHz/mono/16-bit PCM **WAV**;
/// the Volcengine stream wants raw PCM frames (format pcm/codec raw). This pins the
/// header-strip + chunking that bridges the two. The live socket drive is the HITL
/// boundary (mic + network) and isn't unit-tested.
@Suite("VolcengineRealtimeTranscriptionAPI")
struct VolcengineRealtimeTranscriptionAPITests {

    @Test func pcmFramesStripsWavHeaderAndChunks() {
        let pcm = Data((0..<10).map { UInt8($0) })   // 10 bytes of "PCM"
        let wav = Self.makeWAV(pcm: pcm)
        let frames = VolcengineRealtimeTranscriptionAPI.pcmFrames(fromWAV: wav, frameBytes: 4)

        #expect(frames.allSatisfy { $0.count <= 4 })
        #expect(frames.reduce(Data(), +) == pcm)   // reassemble → exactly the PCM, no header
    }

    @Test func pcmFramesFallsBackWhenNoDataChunk() {
        let raw = Data((0..<7).map { UInt8($0) })    // not a WAV — no "data" tag
        let frames = VolcengineRealtimeTranscriptionAPI.pcmFrames(fromWAV: raw, frameBytes: 3)
        #expect(frames.reduce(Data(), +) == raw)
        #expect(frames.count == 3)                   // 3+3+1
    }

    // Minimal canonical 44-byte PCM WAV header + samples.
    private static func makeWAV(pcm: Data) -> Data {
        var d = Data()
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
