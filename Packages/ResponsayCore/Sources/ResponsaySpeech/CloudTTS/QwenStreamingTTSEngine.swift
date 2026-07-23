import Foundation
import ResponsayCore

/// BYOK direct TTS over Qwen-Audio-TTS's DashScope-native WebSocket protocol.
public struct QwenStreamingTTSEngine: StreamingSpeechSynthesizer, SpeechSynthesizer {
    let key: String
    var model = "qwen-audio-3.0-tts-flash"
    var voice = "loongeva_v3.6"
    var region: QwenRealtimeRegion = .china
    var instruction: String?

    public init(
        key: String,
        model: String = "qwen-audio-3.0-tts-flash",
        voice: String = "loongeva_v3.6",
        region: QwenRealtimeRegion = .china,
        instruction: String? = nil
    ) {
        self.key = key
        self.model = model
        self.voice = voice
        self.region = region
        self.instruction = instruction
    }

    public func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        try await collected(text, speed: speed)
    }

    public func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.chunks(from: liveFrames(trimmed, speed: speed))
    }

    static func chunks(
        from frames: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await frame in frames {
                        switch QwenAudioTTSProtocol.decode(frame) {
                        case .audio(let data):
                            continuation.yield(try CloudTTSAudioDecoder.pcm16(
                                data,
                                sampleRate: TTSAudio.defaultSampleRate))
                        case .done:
                            continuation.finish()
                            return
                        case .failure(let message):
                            continuation.finish(throwing: TTSError.synthesisFailed(message))
                            return
                        case .started, .ignored:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func liveFrames(
        _ text: String,
        speed: Double
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            guard !text.isEmpty else {
                continuation.finish(throwing: TTSError.emptyText)
                return
            }
            guard !key.isEmpty else {
                continuation.finish(throwing: TTSError.missingAPIKey(provider: "通义千问"))
                return
            }
            let transport = URLSessionWebSocketTaskTransport()
            let endpoint = QwenAudioTTSEndpoint(region: region)
            let taskID = UUID()
            let key = key
            let model = model
            let voice = voice
            let instruction = instruction
            let task = Task {
                do {
                    await transport.connect(url: endpoint.url, bearerToken: key)
                    try await transport.send(QwenAudioTTSProtocol.runTask(
                        taskID: taskID,
                        model: model,
                        voice: voice,
                        speed: speed,
                        instruction: instruction))
                    var textSent = false
                    while !Task.isCancelled {
                        let frame = try await transport.receive()
                        continuation.yield(frame)
                        switch QwenAudioTTSProtocol.decode(frame) {
                        case .started where !textSent:
                            textSent = true
                            try await transport.send(QwenAudioTTSProtocol.continueTask(
                                taskID: taskID,
                                text: text))
                            try await transport.send(QwenAudioTTSProtocol.finishTask(taskID: taskID))
                        case .done, .failure:
                            continuation.finish()
                            await transport.disconnect()
                            return
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await transport.disconnect()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
