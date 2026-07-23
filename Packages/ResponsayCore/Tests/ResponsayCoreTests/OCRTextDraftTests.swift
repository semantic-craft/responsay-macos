import CoreGraphics
import Testing
@testable import ResponsayCore

struct OCRTextDraftTests {

    @Test func layoutModes_preserveIndependentEdits() {
        let draft = OCRTextDraft(result: result("第一行", "续行"))

        draft.text = "智能版编辑"
        draft.select(.raw)
        #expect(draft.text == "第一行\n续行")

        draft.text = "原始版编辑"
        draft.select(.smart)
        #expect(draft.text == "智能版编辑")
    }

    @Test func replaceResult_resetsBothModeDrafts() {
        let draft = OCRTextDraft(result: result("旧第一行", "旧续行"))
        draft.text = "旧智能编辑"
        draft.select(.raw)
        draft.text = "旧原始编辑"

        draft.replaceResult(result("新第一行", "新续行"))
        #expect(draft.text == "新第一行\n新续行")

        draft.select(.smart)
        #expect(draft.text == "新第一行新续行")
    }

    @Test func cleanupAndRestore_applyOnlyToActiveDraft() {
        let draft = OCRTextDraft(result: result("你 好,", "世界"))
        draft.apply(.cjkSpacing)
        draft.apply(.chinesePunctuation)
        #expect(draft.text == "你好，世界")
        #expect(draft.characterCount == 5)

        draft.restore()
        #expect(draft.text == "你 好,世界")
    }

    private func result(_ first: String, _ second: String) -> OCRResult {
        OCRResult(
            regions: [
                OCRRegion(text: first, boundingBox: CGRect(x: 0, y: 0, width: 100, height: 10), confidence: 1),
                OCRRegion(text: second, boundingBox: CGRect(x: 0, y: 12, width: 100, height: 10), confidence: 1),
            ],
            languages: ["zh-Hans"])
    }
}
