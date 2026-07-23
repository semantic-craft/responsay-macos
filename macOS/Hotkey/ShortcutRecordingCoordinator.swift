import Observation

/// Bridges the settings recorder UI and the live event-tap monitor (`FnHotkeyMonitor`), which live in
/// different layers. The recorder view calls `begin()`; the monitor — while `isRecording` — captures
/// the next key, classifies it, and reports back via `captured` / `rejected`; the view observes those
/// and stores the binding. A shared singleton because there is one global event tap.
@Observable
@MainActor
final class ShortcutRecordingCoordinator {
    static let shared = ShortcutRecordingCoordinator()

    private(set) var isRecording = false
    /// Set by the monitor when a whitelisted combo is captured. The view consumes it then clears it.
    var captured: RecordedShortcut?
    /// Bumped by the monitor when a key press is not in the whitelist, so the view can flash guidance.
    var rejectionCount = 0
    /// Mirrors `isRecording` to the event tap's tap-thread swallow path (set by `FnHotkeyMonitor`),
    /// which must eat every key during recording but can't read this `@MainActor` flag directly.
    @ObservationIgnored var onRecordingChange: (@MainActor (Bool) -> Void)?

    private init() {}

    func begin() {
        captured = nil
        setRecording(true)
    }

    func cancel() {
        setRecording(false)
    }

    /// Called by the monitor (on the main actor) when a valid combo is captured.
    func complete(_ shortcut: RecordedShortcut) {
        captured = shortcut
        setRecording(false)
    }

    /// Called by the monitor when the press was a modifier-bearing key outside the whitelist.
    func reject() {
        rejectionCount += 1
        setRecording(false)
    }

    private func setRecording(_ value: Bool) {
        isRecording = value
        onRecordingChange?(value)
    }
}
