import Foundation
import ResponsayCore

extension OCRTextDraft {
    @MainActor
    func apply(_ action: OCRTextCleanupAction, registeringWith undoManager: UndoManager?) {
        let targetMode = mode
        replaceText(
            action.apply(to: text),
            for: targetMode,
            actionName: action.undoActionName,
            undoManager: undoManager)
    }

    @MainActor
    func restore(registeringWith undoManager: UndoManager?) {
        let targetMode = mode
        replaceText(
            result.displayText(mode: targetMode),
            for: targetMode,
            actionName: "恢复识别文本",
            undoManager: undoManager)
    }

    @MainActor
    private func replaceText(
        _ newValue: String,
        for targetMode: OCRLayoutMode,
        actionName: String,
        undoManager: UndoManager?
    ) {
        let previous = text(for: targetMode)
        let sourceRecognitionRevision = recognitionRevision
        guard newValue != previous else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            guard target.recognitionRevision == sourceRecognitionRevision else { return }
            target.replaceText(
                previous,
                for: targetMode,
                actionName: actionName,
                undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
        setText(newValue, for: targetMode)
    }
}
