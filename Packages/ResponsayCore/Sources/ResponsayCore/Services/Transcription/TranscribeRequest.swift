import Foundation

struct TranscribeRequest: Encodable {
    let audioBase64: String
    let mimeType: String
    let language: String
    let enableITN: Bool
    let provider: String?
    let hotwords: [String]?
    let profile: String?
    /// Custom OpenAI-Whisper-compatible endpoint (ADR-0023). Omitted unless the
    /// `custom-openai` engine is selected.
    var customBaseURL: String? = nil
    var customModel: String? = nil
}
