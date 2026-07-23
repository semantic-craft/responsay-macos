import Testing
import Foundation
@testable import ResponsayCore

/// Pins the shared Whisper-compatible multipart request body used by direct ASR clients.
struct WhisperMultipartRequestTests {
    @Test func build_producesAWhisperMultipartPOST_withAllParts() throws {
        let req = WhisperMultipartRequest.build(
            baseURL: URL(string: "https://api.openai.com/v1")!, key: "sk-test",
            audio: Data("AUDIO".utf8), model: "whisper-1", prompt: "bias terms",
            language: "en", mimeType: "audio/wav")

        #expect(req.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(req.httpMethod == "POST")
        #expect(req.timeoutInterval == 120)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(ct.hasPrefix("multipart/form-data; boundary=Boundary-"))
        let boundary = String(ct.dropFirst("multipart/form-data; boundary=".count))

        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"file\"; filename=\"audio.wav\""))
        #expect(body.contains("Content-Type: audio/wav"))
        #expect(body.contains("AUDIO"))
        #expect(body.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"prompt\"\r\n\r\nbias terms\r\n"))
        #expect(body.hasSuffix("--\(boundary)--\r\n"))
    }

    @Test func build_emptyPrompt_omitsThePromptPart() throws {
        let req = WhisperMultipartRequest.build(
            baseURL: URL(string: "https://x/v1")!, key: "k", audio: Data(), model: "m",
            prompt: "", language: "en", mimeType: "audio/wav")
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(!body.contains("name=\"prompt\""))
    }
}
