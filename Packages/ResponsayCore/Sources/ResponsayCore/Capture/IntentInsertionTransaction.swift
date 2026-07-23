import Foundation

/// What a safe undo should do to the target field. It only ever removes the exact verified text
/// this transaction inserted, or restores the selection it replaced — it NEVER writes the raw
/// transcript back over the document (#560 boundary: Intent-aware never reuses the old
/// "AI 结果换回 raw" revert). When nothing can be proven, it refuses to touch the document.
public enum IntentUndoPlan: Sendable, Equatable {
    /// Swap the inserted text back to the selection it replaced.
    case restoreSelection(replacing: String, with: String)
    /// Delete the inserted text (it landed at a caret, replacing nothing).
    case deleteInserted(String)
    /// The inserted text can't be proven intact — leave the document alone.
    case refuse
}

/// The short-lifecycle undo evidence for one successful Intent-aware insert (#560). It holds only
/// the verified text that was inserted and the selection it replaced — kept just long enough to
/// offer a safe undo, then dropped. It is never persisted as history or learning data.
public struct IntentInsertionTransaction: Sendable, Equatable {
    /// The exact verified text that was inserted.
    public let insertedText: String
    /// The selection present at the target when capture started (what an undo would restore).
    public let priorSelection: SelectionEvidence?

    public init(insertedText: String, priorSelection: SelectionEvidence? = nil) {
        self.insertedText = insertedText
        self.priorSelection = priorSelection
    }

    /// Decide how to undo, given the target field's current text read at undo time. The undo is
    /// only allowed if the inserted text is still provably present (nothing else edited over it);
    /// otherwise it refuses rather than risk corrupting the user's later edits.
    public func undoPlan(currentTargetText: String?) -> IntentUndoPlan {
        guard !insertedText.isEmpty,
              let current = currentTargetText,
              current.contains(insertedText) else {
            return .refuse
        }
        if let priorSelection, priorSelection.hasSelection {
            return .restoreSelection(replacing: insertedText, with: priorSelection.selectedText)
        }
        return .deleteInserted(insertedText)
    }
}
