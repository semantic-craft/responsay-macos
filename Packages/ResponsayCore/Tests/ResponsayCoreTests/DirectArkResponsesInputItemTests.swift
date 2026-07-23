import Testing
@testable import ResponsayCore

/// Regression for the 任意提问 联网搜索 (豆包/Ark `/responses`) 追问 400: a follow-up turn feeds prior
/// assistant history into `input`, and tagging that item `output_text` made Ark demand the
/// `ResponseOutputMessage` fields (`id`/`status`/`type`) → `MissingParameter: input.status`.
/// Every role must map to an `input_text` EasyInputMessage instead — no `status`, no `output_text`.
struct DirectArkResponsesInputItemTests {
    typealias C = DirectArkResponsesStreamingClient

    @Test func assistantHistoryUsesInputTextWithoutStatus() {
        let item = C.inputItem(["role": "assistant", "content": "上一轮的回答"])
        #expect(item["role"] as? String == "assistant")
        #expect(item["status"] == nil)   // the field whose absence 400'd — must stay absent
        let part = (item["content"] as? [[String: Any]])?.first
        #expect(part?["type"] as? String == "input_text")   // not output_text
        #expect(part?["text"] as? String == "上一轮的回答")
    }

    @Test func userAndSystemUnchanged() {
        for role in ["user", "system"] {
            let part = (C.inputItem(["role": role, "content": "q"])["content"] as? [[String: Any]])?.first
            #expect(part?["type"] as? String == "input_text")
        }
    }
}
