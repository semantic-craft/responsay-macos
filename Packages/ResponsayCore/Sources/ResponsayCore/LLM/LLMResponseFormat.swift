import Foundation

/// OpenAI `response_format` (json_schema) contracts for the App-direct path — the Swift mirror of
/// backend `coach_schemas.mjs`. Only sent to LOCAL endpoints (Ollama): a small local model needs
/// the schema to emit valid JSON, while several cloud providers 400 on json_schema, so the cloud
/// path relies on the prompt + tolerant parsing (`LLMChatRequestBuilder` gates this on
/// `endpoint.isLocal`, matching the backend which sent it only for Ollama).
enum LLMResponseFormat {
    private static var string: [String: Any] { ["type": "string"] }
    private static var stringArray: [String: Any] { ["type": "array", "items": ["type": "string"]] }

    /// Schema-less JSON mode — forces the model to emit one valid JSON object without pinning a
    /// per-field schema. Used by the Intent-aware plan compiler on a LOCAL runner (#566): a small
    /// local model needs the nudge to produce parseable JSON, while the deeply-nested `IntentPlan`
    /// strict decoder remains the real contract (a hand-written json_schema for it would drift).
    /// Sent only when `endpoint.isLocal` (the `LLMChatRequestBuilder` gate); the prompt already
    /// demands "one JSON object as raw text", satisfying json_object mode's requirement.
    static var jsonObject: [String: Any] { ["type": "json_object"] }

    private static func schema(_ name: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": name,
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": properties,
                    "required": Array(properties.keys),
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    /// 重改写 / 轻改写 → {text, changes}
    static var textChanges: [String: Any] { schema("rewrite_result", ["text": string, "changes": stringArray]) }
    /// 翻译 → {text, notes}
    static var textNotes: [String: Any] { schema("translate_result", ["text": string, "notes": stringArray]) }
    /// express → {idiomatic, alternatives, reasons, thinkingShift, intentNote}
    static var express: [String: Any] {
        schema("express_coaching", [
            "idiomatic": string, "alternatives": stringArray, "reasons": stringArray,
            "thinkingShift": string, "intentNote": string,
        ])
    }
}
