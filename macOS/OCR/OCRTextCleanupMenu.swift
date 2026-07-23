import Foundation
import ResponsayCore
import SwiftUI

struct OCRTextCleanupMenu: View {
    let draft: OCRTextDraft
    let undoManager: UndoManager?
    let helpText: String

    var body: some View {
        Menu {
            Button("中文标点") { draft.apply(.chinesePunctuation, registeringWith: undoManager) }
            Button("英文标点") { draft.apply(.englishPunctuation, registeringWith: undoManager) }
            Button("清理中文间空格") { draft.apply(.cjkSpacing, registeringWith: undoManager) }
            Divider()
            Button("恢复识别文本") { draft.restore(registeringWith: undoManager) }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel("整理文本")
    }
}
