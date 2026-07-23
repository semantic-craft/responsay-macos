import Foundation
import XCTest
@testable import ResponsayMac
import ResponsayCore

final class OCRTextDraftUndoTests: XCTestCase {

    @MainActor
    func testCleanupRegistersUndoAndRedo() {
        let result = OCRResult(
            text: "你好,世界",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .flowedText)
        let draft = OCRTextDraft(result: result)
        let undoManager = UndoManager()

        draft.apply(.chinesePunctuation, registeringWith: undoManager)
        XCTAssertEqual(draft.text, "你好，世界")

        undoManager.undo()
        XCTAssertEqual(draft.text, "你好,世界")

        undoManager.redo()
        XCTAssertEqual(draft.text, "你好，世界")
    }

    @MainActor
    func testUndoRestoresTheEditedModeAfterSwitchingLayouts() {
        let result = OCRResult(
            text: "你好,世界\n下一行",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .rawLines)
        let draft = OCRTextDraft(result: result)
        let undoManager = UndoManager()

        let originalSmartText = draft.text
        draft.apply(.chinesePunctuation, registeringWith: undoManager)
        draft.select(.raw)
        let originalRawText = draft.text

        undoManager.undo()

        XCTAssertEqual(draft.text, originalRawText)
        draft.select(.smart)
        XCTAssertEqual(draft.text, originalSmartText)
    }

    @MainActor
    func testUndoDoesNotRestoreTextFromPreviousRecognitionResult() {
        let firstResult = OCRResult(
            text: "旧结果,待整理",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .flowedText)
        let replacement = OCRResult(
            text: "新识别结果",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .flowedText)
        let draft = OCRTextDraft(result: firstResult)
        let undoManager = UndoManager()

        draft.apply(.chinesePunctuation, registeringWith: undoManager)
        draft.replaceResult(replacement)
        undoManager.undo()

        XCTAssertEqual(draft.text, "新识别结果")
    }
}
