import Foundation
import Testing
@testable import ResponsayCore

/// #560 — undo may only remove the exact verified text this insert added, or restore the selection
/// it replaced; it refuses when the text can't be proven intact, and NEVER writes the raw
/// transcript back (that boundary belongs to the retired ↩原文 semantics).
struct IntentInsertionUndoTests {
    @Test func caretInsertUndoDeletesTheInsertedText() {
        let tx = IntentInsertionTransaction(insertedText: "周四开会")
        #expect(tx.undoPlan(currentTargetText: "前文 周四开会 后文") == .deleteInserted("周四开会"))
    }

    @Test func selectionReplaceUndoRestoresTheOriginalSelection() {
        let tx = IntentInsertionTransaction(
            insertedText: "修订后的句子",
            priorSelection: SelectionEvidence(selectedText: "原来的句子"))
        #expect(tx.undoPlan(currentTargetText: "开头 修订后的句子 结尾")
            == .restoreSelection(replacing: "修订后的句子", with: "原来的句子"))
    }

    @Test func undoRefusesWhenInsertedTextIsNoLongerPresent() {
        // The user kept typing and edited over the insert → can't prove the range → don't touch it.
        let tx = IntentInsertionTransaction(insertedText: "周四开会")
        #expect(tx.undoPlan(currentTargetText: "完全不同的内容") == .refuse)
    }

    @Test func undoRefusesWhenTargetTextIsUnreadable() {
        let tx = IntentInsertionTransaction(insertedText: "周四开会")
        #expect(tx.undoPlan(currentTargetText: nil) == .refuse)
    }

    @Test func emptyCaretSelectionUndoDeletesRatherThanRestoresEmpty() {
        // A caret (empty selection) must delete, not "restore" an empty string.
        let tx = IntentInsertionTransaction(
            insertedText: "文字", priorSelection: SelectionEvidence(selectedText: ""))
        #expect(tx.undoPlan(currentTargetText: "文字在这") == .deleteInserted("文字"))
    }

    @Test func emptyInsertedTextNeverProducesAnUndo() {
        let tx = IntentInsertionTransaction(insertedText: "")
        #expect(tx.undoPlan(currentTargetText: "anything") == .refuse)
    }
}
