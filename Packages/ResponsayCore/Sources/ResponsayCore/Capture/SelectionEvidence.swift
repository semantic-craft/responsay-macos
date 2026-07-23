import Foundation

/// The minimal selection evidence captured at the target field when a capture starts — just enough
/// to safely restore the user's document on undo (#560). It records the text that was selected (so
/// undo can put it back), not the whole field. A caret with no selection is `selectedText == ""`.
///
/// It is deliberately not persisted beyond the short undo window and never becomes learning data
/// or a raw-transcript store (#560: 只在完成安全撤销所需的生命周期内保留).
public struct SelectionEvidence: Sendable, Equatable {
    /// The exact text selected at the target when capture started ("" for a caret-only position).
    public let selectedText: String

    public init(selectedText: String) {
        self.selectedText = selectedText
    }

    /// Whether the insert will replace a real selection (vs land at a caret).
    public var hasSelection: Bool {
        !selectedText.isEmpty
    }
}
