import XCTest
@testable import ResponsayMac
import ResponsayCore

final class VoiceAssistantResultPanelTests: XCTestCase {
    func testReviewCardReadAloudTextUsesIdiomaticSentenceOnly() {
        let result = ExpressionResult(
            idiomatic: "Could you give me some pointers?",
            original: "please give me some advices",
            reasons: ["不要朗读解释"],
            thinkingShift: "不要朗读思维说明",
            alternatives: ["Any tips?"])

        XCTAssertEqual(
            ReviewCardView.readAloudText(result: result, activeIdiomatic: result.idiomatic),
            "Could you give me some pointers?")
    }

    func testReviewCardReadAloudTextUsesSelectedAlternativeOnly() {
        let result = ExpressionResult(
            idiomatic: "Could you give me some pointers?",
            original: "please give me some advices",
            reasons: ["不要朗读解释"],
            alternatives: ["Any tips?"])

        XCTAssertEqual(
            ReviewCardView.readAloudText(result: result, activeIdiomatic: "  Any tips?  "),
            "Any tips?")
    }

    func testReadAloudTextUsesLatestAssistantAnswerOnly() {
        let messages = [
            VoiceAssistantMessage(role: "user", content: "这个问题不要朗读"),
            VoiceAssistantMessage(role: "assistant", content: "第一个回答"),
            VoiceAssistantMessage(role: "user", content: "追问也不要朗读"),
            VoiceAssistantMessage(role: "assistant", content: "**最终回答**"),
        ]

        XCTAssertEqual(VoiceAssistantResultPanel.readAloudText(from: messages), "最终回答")
    }

    func testReadAloudTextIsEmptyWithoutAssistantAnswer() {
        let messages = [VoiceAssistantMessage(role: "user", content: "只问了问题")]

        XCTAssertEqual(VoiceAssistantResultPanel.readAloudText(from: messages), "")
    }

    // UT-02: Coach 无标准句 → 空(绝不读整段)。
    func testReviewCardReadAloudTextIsEmptyWithoutStandardSentence() {
        XCTAssertTrue(ReviewCardView.readAloudText(result: nil, activeIdiomatic: "anything").isEmpty)

        let result = ExpressionResult(
            idiomatic: "Could you give me some pointers?",
            original: "please give me some advices",
            reasons: ["不要朗读解释"],
            alternatives: [])
        XCTAssertTrue(ReviewCardView.readAloudText(result: result, activeIdiomatic: "   ").isEmpty)
    }
}
