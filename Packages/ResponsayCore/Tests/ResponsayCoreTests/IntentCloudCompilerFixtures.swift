import Foundation
@testable import ResponsayCore

func intentStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [IntentStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

func intentCompletion(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
}

func intentQwenEndpoint(thinkingEnabled: Bool = false) -> LLMEndpoint {
    LLMEndpoint(
        providerId: "qwen",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        model: "qwen-flash",
        apiKey: "sk-1",
        thinkingEnabled: thinkingEnabled)
}

/// A local runner endpoint (#566): loopback base URL, no key (`isLocal` true, `isConfigured` true).
func intentLocalEndpoint() -> LLMEndpoint {
    LLMEndpoint(
        providerId: "ollama",
        baseURL: "http://localhost:11434/v1",
        model: "qwen2.5",
        apiKey: nil)
}

/// The 556 tracer fixture: 「周三开会，不对，周四开会」 → three source units.
let intentCorrectionTranscript = "周三开会，不对，周四开会"

func intentCorrectionInput() -> IntentCompilerInput {
    let units = IntentSourceSegmenter.segment(intentCorrectionTranscript)
    return IntentCompilerInput(
        finalTranscript: intentCorrectionTranscript,
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler,
        sourceUnits: units)
}

/// A verifier-valid near-correction plan for the fixture, as the provider should return it.
func validIntentPlanJSON() -> String {
    let units = IntentSourceSegmenter.segment(intentCorrectionTranscript)
    let references = units.map(IntentPlanPromptBuilder.unitReferenceJSON)
    return """
    {"version": 1, "decision": "render",
     "units": [
       {"source": \(references[0]), "role": "content"},
       {"source": \(references[1]), "role": "correction"},
       {"source": \(references[2]), "role": "content"}],
     "supersessions": [{"winner": \(references[2]), "loser": \(references[0]), "cue": \(references[1])}]}
    """
}
