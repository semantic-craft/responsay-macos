import AppKit

/// Remembers the app that was frontmost when capture started, so inserted text
/// lands back in it even if the review panel briefly took key focus (spec §8/§13.6).
@MainActor
final class TargetAppTracker {
    private(set) var target: NSRunningApplication?

    /// Capture the current frontmost app (ignoring ourselves).
    func capture() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            target = front
        }
    }
}
