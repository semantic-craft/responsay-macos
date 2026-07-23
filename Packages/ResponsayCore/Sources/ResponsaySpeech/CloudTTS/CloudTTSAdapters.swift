import Foundation
import ResponsayCore

// MARK: - Shared helpers

private func jsonRequest(_ url: URL, body: [String: Any], headers: [String: String]) throws -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    return req
}

private func base64Audio(from json: Data, at keyPath: [String]) -> Data? {
    guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
    var node: Any? = obj
    for key in keyPath {
        if let dict = node as? [String: Any] { node = dict[key] }
        else if let arr = node as? [Any], let i = Int(key), i < arr.count { node = arr[i] }
        else { return nil }
    }
    guard let str = node as? String else { return nil }
    return Data(base64Encoded: str)
}

private func hexData(from string: String) -> Data? {
    let hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard hex.count.isMultiple(of: 2) else { return nil }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
        data.append(byte)
        index = next
    }
    return data
}

private func endpoint(_ baseURL: URL, appending component: String) -> URL {
    if baseURL.path.split(separator: "/").last == Substring(component) {
        return baseURL
    }
    return baseURL.appendingPathComponent(component)
}

private func jsonDictionaries(from data: Data) -> [[String: Any]] {
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        return [obj]
    }
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return jsonObjectFragments(in: text).compactMap { fragment in
        guard let data = fragment.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private func jsonObjectFragments(in text: String) -> [String] {
    var fragments: [String] = []
    var depth = 0
    var fragmentStart: String.Index?
    var inString = false
    var escaped = false

    for index in text.indices {
        let char = text[index]
        if inString {
            if escaped { escaped = false }
            else if char == "\\" { escaped = true }
            else if char == "\"" { inString = false }
            continue
        }
        if char == "\"" { inString = true }
        else if char == "{" {
            if depth == 0 { fragmentStart = index }
            depth += 1
        } else if char == "}" {
            depth -= 1
            if depth == 0, let start = fragmentStart {
                fragments.append(String(text[start...index]))
                fragmentStart = nil
            }
        }
    }
    return fragments
}

// MARK: - OpenAI (`gpt-4o-mini-tts` · /audio/speech → raw WAV bytes)

public struct OpenAITTSAdapter: CloudTTSAdapter {
    public var baseURL = URL(string: "https://api.openai.com/v1")!
    public init() {}

    public func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest {
        // `instructions` (style steering) is a future field — add it when 196's voice
        // catalog grows a style option, not before.
        let body: [String: Any] = [
            "model": model, "input": text, "voice": voice,
            "response_format": "wav", "speed": speed,
        ]
        return try jsonRequest(
            baseURL.appendingPathComponent("audio/speech"),
            body: body,
            headers: ["Authorization": "Bearer \(key)"])
    }

    public func decode(_ data: Data) throws -> SynthesizedSpeech { try CloudTTSAudioDecoder.wav(data) }
}

// MARK: - MiMo (`mimo-v2.5-tts` · OpenAI-compatible /chat/completions → one-shot WAV)

public struct MiMoTTSAdapter: CloudTTSAdapter {
    public var baseURL = URL(string: "https://api.xiaomimimo.com/v1")!
    public init() {}

    public func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest {
        // Non-streaming: one POST returns the whole WAV (docs「非流式调用」). The streaming
        // chat-completions path stalled with no audio; this mirrors MiniMax's batch shape.
        // The text to speak goes in an `assistant` message (per docs); `speed` has no
        // structured field — MiMo controls pace via natural-language/tag prompts, not a param.
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "assistant", "content": text]],
            "audio": ["format": "wav", "voice": voice],
        ]
        // MiMo Token Plan uses an `api-key` header with the tp-... key.
        return try jsonRequest(
            baseURL.appendingPathComponent("chat/completions"),
            body: body, headers: ["api-key": key])
    }

    public func decode(_ data: Data) throws -> SynthesizedSpeech {
        guard let wav = base64Audio(from: data, at: ["choices", "0", "message", "audio", "data"]) else {
            throw TTSError.providerReturnedNoAudio(provider: "MiMo")
        }
        return try CloudTTSAudioDecoder.wav(wav)
    }
}

// MARK: - MiniMax (`speech-2.8-*` · /t2a_v2 → hex WAV)

public struct MiniMaxTTSAdapter: CloudTTSAdapter {
    public var baseURL = URL(string: "https://api.minimaxi.com/v1")!
    public init() {}

    public func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "text": text,
            "stream": false,
            "voice_setting": [
                "voice_id": voice,
                "speed": speed,
                "vol": 1,
                "pitch": 0,
            ],
            "audio_setting": [
                "sample_rate": 32_000,
                "bitrate": 128_000,
                "format": "wav",
                "channel": 1,
            ],
            "subtitle_enable": false,
            "output_format": "hex",
        ]
        return try jsonRequest(
            endpoint(baseURL, appending: "t2a_v2"),
            body: body,
            headers: ["Authorization": "Bearer \(key)"])
    }

    public func decode(_ data: Data) throws -> SynthesizedSpeech {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TTSError.providerReturnedNoAudio(provider: "MiniMax")
        }
        if let base = obj["base_resp"] as? [String: Any],
           let status = base["status_code"] as? Int,
           status != 0 {
            let message = base["status_msg"] as? String ?? "MiniMax 语音合成错误"
            throw TTSError.synthesisFailed(message)
        }
        guard let payload = obj["data"] as? [String: Any],
              let hex = payload["audio"] as? String,
              let audio = hexData(from: hex) else {
            throw TTSError.providerReturnedNoAudio(provider: "MiniMax")
        }
        return try CloudTTSAudioDecoder.wav(audio)
    }
}

// MARK: - Volcengine (`seed-tts-2.0` · HTTP chunked JSON → base64 PCM)

public struct VolcengineTTSAdapter: CloudTTSAdapter {
    public var baseURL = URL(string: "https://openspeech.bytedance.com/api/v3")!
    public init() {}

    public func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest {
        let url = baseURL.path.hasSuffix("/tts/unidirectional")
            ? baseURL
            : baseURL.appendingPathComponent("tts").appendingPathComponent("unidirectional")
        let speechRate = min(100, max(-50, Int(((speed - 1.0) * 100).rounded())))
        let body: [String: Any] = [
            "user": [
                "uid": "responsay-macos",
            ],
            "req_params": [
                "text": text,
                "speaker": voice,
                "audio_params": [
                    "format": "pcm",
                    "sample_rate": TTSAudio.defaultSampleRate,
                    "speech_rate": speechRate,
                ],
            ],
        ]
        return try jsonRequest(
            url,
            body: body,
            headers: [
                "X-Api-Key": key,
                "X-Api-Resource-Id": model,
                "X-Api-Request-Id": UUID().uuidString,
            ])
    }

    public func decode(_ data: Data) throws -> SynthesizedSpeech {
        var pcm = Data()
        for obj in jsonDictionaries(from: data) {
            let code = (obj["code"] as? Int) ?? Int(obj["code"] as? String ?? "0") ?? 0
            if code == 20000000 { continue }
            guard code == 0 else {
                throw TTSError.synthesisFailed(obj["message"] as? String ?? "火山引擎语音合成错误")
            }
            if let base64 = obj["data"] as? String,
               let chunk = Data(base64Encoded: base64) {
                pcm.append(chunk)
            }
        }
        guard !pcm.isEmpty else {
            throw TTSError.providerReturnedNoAudio(provider: "火山引擎")
        }
        return try CloudTTSAudioDecoder.pcm16(pcm, sampleRate: TTSAudio.defaultSampleRate)
    }
}

// MARK: - Gemini (`gemini-*-tts` · :generateContent → base64 PCM16 @ 24k)

public struct GeminiTTSAdapter: CloudTTSAdapter {
    public var baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    public init() {}

    public func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest {
        let body: [String: Any] = [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]],
            ],
        ]
        let url = baseURL.appendingPathComponent("models/\(model):generateContent")
        return try jsonRequest(url, body: body, headers: ["x-goog-api-key": key])
    }

    public func decode(_ data: Data) throws -> SynthesizedSpeech {
        guard let pcm = base64Audio(
            from: data, at: ["candidates", "0", "content", "parts", "0", "inlineData", "data"]) else {
            throw TTSError.providerReturnedNoAudio(provider: "Gemini")
        }
        return try CloudTTSAudioDecoder.pcm16(pcm, sampleRate: TTSAudio.defaultSampleRate)
    }
}
