import Foundation

/// The minimal identity of the field a verified result is bound to, captured both at capture start
/// and again right before commit (#560). Comparing the two proves whether the target is still the
/// same one — so content generated for one field is never silently written into another that
/// happened to gain focus while the plan compiled.
///
/// The macOS host fills this from Accessibility (bundle id, pid, window title, editability, and the
/// current selection); Core keeps it host-agnostic so the drift decision stays unit-testable.
public struct InsertionTargetSnapshot: Sendable, Equatable {
    /// The frontmost app's bundle identifier (`nil` when none could be identified).
    public let bundleID: String?
    /// The owning process id — distinguishes a relaunched app that reused the same bundle id.
    public let processID: Int32?
    /// The focused window / scene title, best-effort (`nil` when unreadable).
    public let windowTitle: String?
    /// Whether the focused element can currently receive text.
    public let isEditable: Bool
    /// The selection at this moment, for undo restoration.
    public let selection: SelectionEvidence?

    public init(
        bundleID: String?,
        processID: Int32? = nil,
        windowTitle: String? = nil,
        isEditable: Bool,
        selection: SelectionEvidence? = nil
    ) {
        self.bundleID = bundleID
        self.processID = processID
        self.windowTitle = windowTitle
        self.isEditable = isEditable
        self.selection = selection
    }
}
