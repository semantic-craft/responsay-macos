import Foundation
import ResponsayCore

/// BYOK direct-to-provider cloud TTS (issue 195). The app holds the user's key in
/// the Keychain (`ProviderCredentialStore`) and calls the provider directly — the
/// same posture as realtime ASR and the reference extensions, NOT backend-mediated.
/// A `SpeechSynthesizer`, so it feeds the same read-aloud pipeline (194) as Kokoro.
///
/// Per-provider request/response shapes live in `CloudTTSAdapter` conformers,
/// implemented faithfully from the verified extension source (ai-voice-studio).
public struct DirectCloudTTSEngine: SpeechSynthesizer {
    let adapter: any CloudTTSAdapter
    let model: String
    let voice: String
    let key: String
    /// Injectable for headless tests (stub URLProtocol); production uses `.shared`.
    let session: URLSession

    public init(adapter: any CloudTTSAdapter, model: String, voice: String, key: String,
                session: URLSession = .shared) {
        self.adapter = adapter
        self.model = model
        self.voice = voice
        self.key = key
        self.session = session
    }

    public func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }
        let request = try adapter.makeRequest(
            text: trimmed, model: model, voice: voice,
            speed: Self.clampSpeed(speed), key: key)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TTSError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TTSError.network("无 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TTSError.http(status: http.statusCode)
        }
        return try adapter.decode(data)
    }
}

/// One cloud provider's TTS HTTP shape (issue 195). `makeRequest` builds the BYOK
/// request; `decode` turns the response body into audio.
public protocol CloudTTSAdapter: Sendable {
    func makeRequest(text: String, model: String, voice: String, speed: Double, key: String) throws -> URLRequest
    func decode(_ data: Data) throws -> SynthesizedSpeech
}
