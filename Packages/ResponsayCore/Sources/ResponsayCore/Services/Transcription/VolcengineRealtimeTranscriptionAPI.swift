import Foundation

/// Whole-clip transcription over the Volcengine 大模型流式 (`bigmodel_nostream`) socket:
/// on `stop()` the recorded clip is replayed as audio frames at full speed and the
/// cumulative final is returned — lower stop-to-final latency than the async
/// submit/query 录音文件 path, and the groundwork for true live-mic streaming.
///
/// Conforms to `TranscriptionAPI` (final-only), NOT `StreamingTranscriptionAPI`:
/// Volcengine resends the *cumulative* transcript each packet, which does not map to
/// the delta-accumulating capsule-preview consumer without lossy diffing. Live
/// typewriter preview (and live-mic push) are the follow-up — same deliberate
/// final-only stance as qwen-asr-flash (`usesPostUploadStreamingPreview`).
///
/// The socket drive touches mic-recorded audio + network and is the HITL boundary;
/// the WAV→PCM framing (`pcmFrames`) and the wire codec/fold are unit-tested offline.
public struct VolcengineRealtimeTranscriptionAPI: TranscriptionAPI {
    let endpoint: VolcengineRealtimeEndpoint
    let config: VolcengineRealtimeConfig
    let session: URLSession
    /// ~1s of 16 kHz/16-bit/mono PCM per frame; a recorded clip is pumped as a burst.
    let frameBytes: Int

    public init(
        endpoint: VolcengineRealtimeEndpoint,
        config: VolcengineRealtimeConfig = VolcengineRealtimeConfig(),
        session: URLSession = .shared,
        frameBytes: Int = 32_000
    ) {
        self.endpoint = endpoint
        self.config = config
        self.session = session
        self.frameBytes = frameBytes
    }

    public func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        guard !endpoint.apiKey.isEmpty else {
            throw CoachAPIError.message("未配置火山引擎 API Key。请在设置中配置。")
        }
        let socket = session.webSocketTask(with: endpoint.makeRequest(connectID: UUID().uuidString))
        socket.resume()
        let client = VolcengineRealtimeClient(transport: socket)
        do {
            try await client.sendFullClientRequest(config: config)
            // ponytail: sequential send-then-drain is fine for short dictation clips; a
            // long clip may need concurrent send/receive to avoid socket backpressure.
            for frame in Self.pcmFrames(fromWAV: audio, frameBytes: frameBytes) {
                try await client.sendAudio(frame)
            }
            try await client.sendFinish()   // empty LAST_PACKET frame = end of input
            let text = try await Self.drainFinal(from: client)
            socket.cancel(with: .normalClosure, reason: nil)
            return TranscriptionResult(
                text: text, model: "bigmodel", language: "auto", provider: "volcengine-realtime")
        } catch {
            socket.cancel(with: .abnormalClosure, reason: nil)
            throw error
        }
    }

    /// Read server frames until the terminal (`isLast`) transcript arrives.
    private static func drainFinal(from client: VolcengineRealtimeClient) async throws -> String {
        while true {
            let message = try await client.receive()
            switch await client.handleEvent(message) {
            case .final(let text):
                return text
            case .failed(let reason):
                throw CoachAPIError.message(reason ?? "火山引擎流式识别失败")
            case .partial, .none:
                continue
            }
        }
    }

    /// Strip the WAV header (the capture layer sends a 16 kHz/mono/16-bit PCM WAV) and
    /// chunk the raw PCM into frames. Falls back to treating the whole input as PCM if
    /// no `data` subchunk is found.
    public static func pcmFrames(fromWAV wav: Data, frameBytes: Int) -> [Data] {
        let pcm = stripWAVHeader(wav)
        guard frameBytes > 0, !pcm.isEmpty else { return pcm.isEmpty ? [] : [pcm] }
        var frames: [Data] = []
        var index = pcm.startIndex
        while index < pcm.endIndex {
            let end = pcm.index(index, offsetBy: frameBytes, limitedBy: pcm.endIndex) ?? pcm.endIndex
            frames.append(Data(pcm[index..<end]))
            index = end
        }
        return frames
    }

    private static func stripWAVHeader(_ wav: Data) -> Data {
        // PCM begins 8 bytes after the "data" tag (4 tag + 4 size).
        let dataTag: [UInt8] = [0x64, 0x61, 0x74, 0x61]
        let bytes = [UInt8](wav)
        guard bytes.count >= dataTag.count else { return wav }
        for start in 0...(bytes.count - dataTag.count) where Array(bytes[start..<start + 4]) == dataTag {
            let pcmStart = start + 8
            return pcmStart <= bytes.count ? Data(bytes[pcmStart...]) : Data()
        }
        return wav   // not a recognizable WAV → treat as raw PCM
    }
}
