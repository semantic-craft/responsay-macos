import Foundation
import Testing
@testable import ResponsayCore

/// Pins the Volcengine bidirectional-streaming ASR binary protocol
/// (`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`). Constants and
/// framing verified against ByteDance's published protocol / a working reference
/// client (koe `doubao.rs`): 4-byte header, big-endian length prefix, gzip payloads.
@Suite("Volcengine realtime protocol")
struct VolcengineRealtimeProtocolTests {
    typealias P = VolcengineRealtimeProtocol

    // MARK: - Client → server

    @Test func fullClientRequestHeaderAndJSON() throws {
        let config = VolcengineRealtimeConfig(
            sampleRate: 16000, enableITN: true, enablePunc: true,
            hotwords: ["法言", "Responsay"])
        let frame = P.fullClientRequest(config: config)

        // Header: version 1 / size 1, FULL_CLIENT_REQUEST+no-flag, JSON+gzip, reserved.
        #expect(Array(frame.prefix(4)) == [0x11, 0x10, 0x11, 0x00])

        // 4-byte big-endian payload length, then gzip(JSON).
        let payload = frame.suffix(from: 8)
        #expect(payload.count == Self.readBE(frame, at: 4))

        let json = try #require(
            try JSONSerialization.jsonObject(with: Gzip.decompress(Data(payload))) as? [String: Any])
        let audio = try #require(json["audio"] as? [String: Any])
        #expect(audio["format"] as? String == "pcm")
        #expect(audio["codec"] as? String == "raw")
        #expect(audio["rate"] as? Int == 16000)
        #expect(audio["bits"] as? Int == 16)
        #expect(audio["channel"] as? Int == 1)

        let request = try #require(json["request"] as? [String: Any])
        #expect(request["model_name"] as? String == "bigmodel")
        #expect(request["enable_itn"] as? Bool == true)
        #expect(request["enable_punc"] as? Bool == true)
        #expect(request["show_utterances"] as? Bool == true)

        // Hotwords ride inside request.corpus.context as a JSON *string* (ByteDance shape).
        let corpus = try #require(request["corpus"] as? [String: Any])
        let contextString = try #require(corpus["context"] as? String)
        let contextJSON = try #require(
            try JSONSerialization.jsonObject(with: Data(contextString.utf8)) as? [String: Any])
        let words = try #require(contextJSON["hotwords"] as? [[String: Any]])
        #expect(words.compactMap { $0["word"] as? String } == ["法言", "Responsay"])
    }

    @Test func audioFrameCarriesGzippedPCMAndLastFlag() throws {
        let pcm = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        let mid = P.audioFrame(pcm, isLast: false)
        #expect(Array(mid.prefix(4)) == [0x11, 0x20, 0x01, 0x00])   // AUDIO_ONLY, no flag, raw+gzip

        let last = P.audioFrame(pcm, isLast: true)
        #expect(Array(last.prefix(4)) == [0x11, 0x22, 0x01, 0x00])  // AUDIO_ONLY, LAST_PACKET flag

        // Payload round-trips back to the original PCM.
        #expect(try Gzip.decompress(Data(last.suffix(from: 8))) == pcm)
    }

    // MARK: - Server → client

    @Test func parsesPartialResponse() throws {
        let frame = Self.serverFrame(
            json: #"{"result":{"text":"你好","utterances":[{"text":"你好","definite":false}]}}"#,
            isLast: false)
        #expect(try P.parse(frame) == .response(text: "你好", isDefinite: false, isLast: false))
    }

    @Test func parsesDefiniteSegment() throws {
        let frame = Self.serverFrame(
            json: #"{"result":{"text":"你好世界","utterances":[{"text":"你好世界","definite":true}]}}"#,
            isLast: false)
        #expect(try P.parse(frame) == .response(text: "你好世界", isDefinite: true, isLast: false))
    }

    @Test func parsesFinalWhenLastPacketFlagSet() throws {
        let frame = Self.serverFrame(
            json: #"{"result":{"text":"最终结果","utterances":[{"text":"最终结果","definite":true}]}}"#,
            isLast: true)
        #expect(try P.parse(frame) == .response(text: "最终结果", isDefinite: true, isLast: true))
    }

    /// Optimized async mode tags responses with a sequence number (flag bit0); the
    /// parser must skip the 4-byte sequence before the payload length.
    @Test func parsesResponseWithSequenceNumber() throws {
        let frame = Self.serverFrame(
            json: #"{"result":{"text":"带序号","utterances":[]}}"#,
            isLast: false, sequence: 7)
        #expect(try P.parse(frame) == .response(text: "带序号", isDefinite: false, isLast: false))
    }

    @Test func parsesErrorFrame() throws {
        let frame = Self.errorFrame(code: 45000001, message: "quota exceeded")
        #expect(try P.parse(frame) == .error(code: 45000001, message: "quota exceeded"))
    }

    // MARK: - Server-frame builders (mirror the wire format the service emits)

    private static func serverFrame(json: String, isLast: Bool, sequence: UInt32? = nil) -> Data {
        var flags: UInt8 = isLast ? 0b0010 : 0b0000
        if sequence != nil { flags |= 0b0001 }
        var out = Data([0x11, (0b1001 << 4) | flags, 0x11, 0x00])   // SERVER_RESPONSE, JSON+gzip
        if let sequence { appendBE(sequence, to: &out) }
        let payload = Gzip.compress(Data(json.utf8))
        appendBE(UInt32(payload.count), to: &out)
        out.append(payload)
        return out
    }

    private static func errorFrame(code: UInt32, message: String) -> Data {
        var out = Data([0x11, (0b1111 << 4) | 0x00, 0x11, 0x00])    // ERROR, JSON+gzip (payload uncompressed here)
        appendBE(code, to: &out)
        let msg = Data(message.utf8)
        appendBE(UInt32(msg.count), to: &out)
        out.append(msg)
        return out
    }

    private static func appendBE(_ value: UInt32, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private static func readBE(_ data: Data, at offset: Int) -> Int {
        let base = data.startIndex + offset
        let b0 = Int(data[base]) << 24
        let b1 = Int(data[base + 1]) << 16
        let b2 = Int(data[base + 2]) << 8
        let b3 = Int(data[base + 3])
        return b0 + b1 + b2 + b3
    }
}

@Test func requestJSON_carriesIntentFriendlySegmentationParams() throws {
    // #579 — semantic segmentation widened + two-pass finalization for 口述释字.
    func requestBlock(_ config: VolcengineRealtimeConfig) throws -> [String: Any] {
        let frame = VolcengineRealtimeProtocol.fullClientRequest(config: config)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Gzip.decompress(Data(frame.suffix(from: 8)))) as? [String: Any])
        return try #require(json["request"] as? [String: Any])
    }

    let tuned = try requestBlock(VolcengineRealtimeConfig(vadSegmentDuration: 8000, enableTwoPass: true))
    #expect(tuned["vad_segment_duration"] as? Int == 8000)
    #expect(tuned["enable_nonstream"] as? Bool == true)
    #expect(tuned["end_window_size"] == nil)

    // Defaults stay inert — nothing new rides along unless opted in.
    let plain = try requestBlock(VolcengineRealtimeConfig())
    #expect(plain["vad_segment_duration"] == nil)
    #expect(plain["enable_nonstream"] == nil)
}
