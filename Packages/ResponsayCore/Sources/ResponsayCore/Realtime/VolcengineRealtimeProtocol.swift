import Foundation

/// Codec for the Volcengine 大模型流式语音识别 binary WebSocket protocol
/// (`/api/v3/sauc/bigmodel_nostream`, 流式输入模式 #580). A 4-byte header
/// `[version|size, type|flags, serial|compress, reserved]` precedes a 4-byte
/// big-endian length and a (gzip) payload. Constants verified against ByteDance's
/// published protocol and a working reference client (koe `doubao.rs`). Pure and
/// synchronous so the framing is fully unit-testable without a socket.
public enum VolcengineRealtimeProtocol {
    /// A decoded server frame. `text` is the *cumulative* transcript so far (the
    /// service resends the whole text each packet), so no per-sentence joining is
    /// needed — unlike DashScope Fun-ASR. `isDefinite` marks a finalized segment;
    /// `isLast` marks the terminal packet for the utterance.
    public enum ServerMessage: Equatable, Sendable {
        case response(text: String, isDefinite: Bool, isLast: Bool)
        case error(code: UInt32, message: String)
    }

    public enum Failure: Error, Sendable {
        case frameTooShort
        case unknownMessageType(UInt8)
        case badPayload
    }

    // MARK: - Protocol constants (koe doubao.rs)

    private static let protocolVersion: UInt8 = 0b0001
    private static let headerSize: UInt8 = 0b0001            // × 4 = 4 bytes
    private static let msgFullClientRequest: UInt8 = 0b0001
    private static let msgAudioOnly: UInt8 = 0b0010
    private static let msgServerResponse: UInt8 = 0b1001
    private static let msgError: UInt8 = 0b1111
    private static let flagNone: UInt8 = 0b0000
    private static let flagLastPacket: UInt8 = 0b0010
    private static let flagHasSequence: UInt8 = 0b0001
    private static let serialNone: UInt8 = 0b0000
    private static let serialJSON: UInt8 = 0b0001
    private static let compressGzip: UInt8 = 0b0001

    // MARK: - Client → server

    /// The full-client-request frame: gzip(JSON) with audio config + recognition params.
    public static func fullClientRequest(config: VolcengineRealtimeConfig) -> Data {
        let jsonData = (try? JSONSerialization.data(withJSONObject: requestJSON(config))) ?? Data()
        return frame(
            header: header(msgFullClientRequest, flagNone, serialJSON, compressGzip),
            payload: Gzip.compress(jsonData))
    }

    /// One audio frame: gzip(PCM). `isLast` sets the LAST_PACKET flag (an empty
    /// last frame is the end-of-input signal — matches the reference client).
    public static func audioFrame(_ pcm: Data, isLast: Bool) -> Data {
        frame(
            header: header(msgAudioOnly, isLast ? flagLastPacket : flagNone, serialNone, compressGzip),
            payload: Gzip.compress(pcm))
    }

    // MARK: - Server → client

    public static func parse(_ data: Data) throws -> ServerMessage {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw Failure.frameTooShort }
        let msgType = (bytes[1] >> 4) & 0x0F
        let flags = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        var offset = Int(bytes[0] & 0x0F) * 4   // header size is in 4-byte words

        if msgType == msgServerResponse {
            if flags & flagHasSequence != 0 { offset += 4 }   // skip sequence number
            guard bytes.count >= offset + 4 else { throw Failure.badPayload }
            let size = Int(readBE(bytes, offset)); offset += 4
            guard bytes.count >= offset + size else { throw Failure.badPayload }
            let raw = Data(bytes[offset ..< offset + size])
            let jsonData = compression == compressGzip ? try Gzip.decompress(raw) : raw
            guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let result = root["result"] as? [String: Any] else {
                throw Failure.badPayload
            }
            let text = result["text"] as? String ?? ""
            let utterances = result["utterances"] as? [[String: Any]] ?? []
            let isDefinite = utterances.contains { ($0["definite"] as? Bool) == true }
            return .response(text: text, isDefinite: isDefinite, isLast: flags & flagLastPacket != 0)
        }

        if msgType == msgError {
            let code = bytes.count >= offset + 4 ? readBE(bytes, offset) : 0
            offset += 4
            var message = ""
            if bytes.count >= offset + 4 {
                let size = Int(readBE(bytes, offset)); offset += 4
                if bytes.count >= offset + size {
                    message = String(bytes: bytes[offset ..< offset + size], encoding: .utf8) ?? ""
                }
            }
            return .error(code: code, message: message)
        }

        throw Failure.unknownMessageType(msgType)
    }

    // MARK: - Framing

    private static func header(_ msg: UInt8, _ flags: UInt8, _ serial: UInt8, _ compress: UInt8) -> [UInt8] {
        [(protocolVersion << 4) | headerSize, (msg << 4) | flags, (serial << 4) | compress, 0x00]
    }

    private static func frame(header: [UInt8], payload: Data) -> Data {
        var out = Data(header)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    private static func readBE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        let b0 = UInt32(bytes[offset]) << 24
        let b1 = UInt32(bytes[offset + 1]) << 16
        let b2 = UInt32(bytes[offset + 2]) << 8
        let b3 = UInt32(bytes[offset + 3])
        return b0 | b1 | b2 | b3
    }

    // MARK: - Request JSON (koe doubao.rs shape)

    private static func requestJSON(_ config: VolcengineRealtimeConfig) -> [String: Any] {
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": config.enableITN,
            "enable_punc": config.enablePunc,
            "enable_ddc": config.enableDDC,
            "result_type": "full",
            "show_utterances": true,
        ]
        if let endWindowSize = config.endWindowSize {
            request["end_window_size"] = endWindowSize
        }
        if let vadSegmentDuration = config.vadSegmentDuration {
            request["vad_segment_duration"] = vadSegmentDuration
        }
        if config.enableTwoPass {
            request["enable_nonstream"] = true
        }
        if !config.hotwords.isEmpty {
            // Hotwords go into corpus.context as a JSON *string* of {hotwords:[{word}]}.
            let words = config.hotwords.map { ["word": $0] }
            if let data = try? JSONSerialization.data(withJSONObject: ["hotwords": words]),
               let string = String(data: data, encoding: .utf8) {
                request["corpus"] = ["context": string]
            }
        }
        var audio: [String: Any] = [
            "format": "pcm",
            "codec": "raw",
            "rate": config.sampleRate,
            "bits": 16,
            "channel": 1,
        ]
        if let language = config.language, !language.isEmpty {
            audio["language"] = language
        }
        return ["user": ["uid": "responsay"], "audio": audio, "request": request]
    }
}
