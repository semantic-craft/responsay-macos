import AppKit
import ResponsayCore

/// Owns the OS-event **lifecycle interrupts** extracted from `CaptureController.start()`:
/// defaults-change re-sync, sleep/wake session recovery, and the global Esc abort.
///
/// `start()` installs the four subscriptions (NSNotification + a global `.keyDown` monitor) and
/// keeps them thin — each forwards to a plain `handle*` method that calls an injected closure. The
/// handlers are the unit-testable seam (inject recording closures, call directly, assert); the
/// registration itself is OS-bound → HITL, not unit-tested.
///
/// The three closures wire to the coordinator's collaborators in production:
/// `reSyncHotkeys` → `hotkeyDispatcher.syncFnMonitor`, `cancelCapture` → `vm.cancelCapture`,
/// `handleEscape` → `escapeController.handleEscape`.
@MainActor
final class StateOrchestrator {
    private let reSyncHotkeys: () -> Void
    private let cancelCapture: () async -> Void
    private let handleEscape: () async -> Void

    /// Global Esc observer so a mistaken capture can be aborted without inserting (STATE-CANCEL-002).
    private var escMonitor: Any?

    /// macOS virtual keyCode for Escape.
    private let escapeKeyCode: UInt16 = 53

    init(
        reSyncHotkeys: @escaping () -> Void,
        cancelCapture: @escaping () async -> Void,
        handleEscape: @escaping () async -> Void
    ) {
        self.reSyncHotkeys = reSyncHotkeys
        self.cancelCapture = cancelCapture
        self.handleEscape = handleEscape
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDefaultsChanged() }
        }

        // STATE-SLEEP-004 / HOTKEY-STUCK-004: a capture active across sleep (or whose Fn key-up
        // was lost) is never expired by the OS. Cancel a stranded session on sleep/wake and
        // re-arm the Fn monitor on wake so a lost flags-changed event can't strand the mic.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.handleSleep() }
            }
        }
        workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.handleWake() }
            }
        }

        // STATE-CANCEL-002: Esc aborts an in-flight capture (the capsules are non-activating,
        // click-through panels, so a global monitor is the only way to hear the key). Observe-only:
        // Esc still reaches the focused app; we only act while a capture-like flow is listening —
        // dictation OR 任意提问 (routed by `escapeController`).
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cheap synchronous filter on the hot path: this monitor fires for *every* global
            // keystroke, so pre-filter to Esc before spawning a Task (keep this guard — `handleEscapeKey`
            // re-checks only to stay independently testable; dropping this one spawns a Task per keystroke).
            guard event.keyCode == 53 else { return }   // kVK_Escape
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleEscapeKey(keyCode: event.keyCode)
            }
        }
    }

    // MARK: - Handlers (testable seam)

    func handleDefaultsChanged() {
        reSyncHotkeys()
    }

    func handleSleep() async {
        await cancelCapture()
    }

    /// Re-arm the Fn monitor **before** cancelling a stranded session (order preserved from the
    /// original wake observer: a lost flags-changed event can't strand the mic once re-synced).
    func handleWake() async {
        reSyncHotkeys()
        await cancelCapture()
    }

    func handleEscapeKey(keyCode: UInt16) async {
        guard keyCode == escapeKeyCode else { return }
        await handleEscape()
    }
}
