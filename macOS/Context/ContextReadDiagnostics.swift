import Foundation

/// Read-only diagnostics about *why* a cursor-context read succeeded or failed, used by the
/// context-probe matrix (`scripts/macos-context-matrix.mjs`) to classify each app as
/// readable / needs-a11y / unsupported. Never sent to the backend — it is measurement only.
struct ContextReadDiagnostics: Sendable, Equatable {
    /// AXRole of the element we read text from (or the focused element when none was usable).
    let role: String?
    /// Whether any element exposing text context was found at all.
    let hasTextElement: Bool
    /// Whether an element exposes `AXSelectedTextMarkerRange` (the web/contenteditable marker path).
    let markerCapable: Bool

    static let empty = ContextReadDiagnostics(role: nil, hasTextElement: false, markerCapable: false)
}
