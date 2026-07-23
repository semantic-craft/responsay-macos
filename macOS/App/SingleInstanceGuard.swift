import AppKit

/// Prevents a second running instance from registering the same global hotkeys and mic
/// engine (INSTANCE-DOUBLE-001). The app is unsandboxed (Developer ID) and sets no
/// `LSMultipleInstancesProhibited`, so a copy launched from a different path — or the brief
/// window during a Sparkle update swap — would otherwise double-capture and double-insert.
enum SingleInstanceGuard {
    /// Pure decision core (unit-testable): is another instance live besides us?
    static func hasDuplicate(currentPID: pid_t, runningPIDs: [pid_t]) -> Bool {
        runningPIDs.contains { $0 != currentPID }
    }

    /// True when another running app shares our bundle identifier.
    @MainActor
    static func isDuplicateInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current.processIdentifier
        let pids = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)
        return hasDuplicate(currentPID: current, runningPIDs: pids)
    }

    /// If a duplicate is already running, bring the original forward and terminate self.
    /// Returns `true` when the caller should abort launch.
    @MainActor
    @discardableResult
    static func terminateIfDuplicate() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != current }
        guard let original = others.first else { return false }
        original.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }
}
