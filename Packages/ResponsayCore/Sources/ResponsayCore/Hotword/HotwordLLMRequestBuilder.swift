import Foundation

public enum HotwordLLMRequestBuilder {
    /// Build the extraction request from ONLY the word pairs the user actually changed
    /// (`substitutions`), not the whole before/after text. Sending the full text let the model
    /// harvest every entity-shaped token that merely happened to be on screen (librime,
    /// responsay.com, …) even though the user never spoke or corrected it; grounding the prompt in
    /// the edit diff is what keeps the dictionary honest. App/window are deliberately NOT sent —
    /// they were a second junk source — and are attached to the candidate afterwards for the audit
    /// panel only.
    public static func makeRequest(
        endpoint: LLMEndpoint,
        source: HotwordLearningSource,
        substitutions: [WordSubstitution]
    ) throws -> URLRequest {
        try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: systemPrompt(source: source),
            user: userPrompt(substitutions: substitutions),
            responseFormat: responseFormat,
            generationAction: .rewrite,
            timeout: 12)
    }

    private static func systemPrompt(source: HotwordLearningSource) -> String {
        """
        你是 Responsay 的个人词典候选词抽取器。用户刚刚把语音识别结果里的几个词改掉了，下面只给你这些被改动的「原文→改正后」词对。
        只针对这些「改正后」的词，判断哪些是语音听错的专名、术语、人名、项目代号或品牌词，值得加入识别词典。
        严格规则：没有列在词对里的词一律不要提；不要猜测、不要改写正文、不要返回完整文本；如果都不是听错的术语，就返回空数组。
        只输出一个 JSON 对象: {"candidates":[{"term":string,"confidence":number,"reason":string}]}。当前抽取来源: \(source.displayName)。
        """
    }

    private static func userPrompt(substitutions: [WordSubstitution]) -> String {
        let edits = substitutions
            .map { "- 「\($0.from)」→「\($0.to)」" }
            .joined(separator: "\n")
        return """
        用户改动的词对（原文 → 改正后）:
        \(edits)
        """
    }

    private static var responseFormat: [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "hotword_candidates",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "candidates": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "term": ["type": "string"],
                                    "confidence": ["type": "number"],
                                    "reason": ["type": "string"],
                                ],
                                "required": ["term", "confidence", "reason"],
                                "additionalProperties": false,
                            ],
                        ],
                    ],
                    "required": ["candidates"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}
