import AppKit
import OSLog
import os
import ResponsayCore

enum NativeHotkeyEvent: Equatable, Sendable {
    case flagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags)
    case keyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags)
    case keyUp(keyCode: UInt16)

    static func make(type: CGEventType, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) -> Self? {
        switch type {
        case .flagsChanged:
            return .flagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        case .keyDown:
            return .keyDown(keyCode: keyCode, modifierFlags: modifierFlags)
        case .keyUp:
            return .keyUp(keyCode: keyCode)
        default:
            return nil
        }
    }

    static func make(type: CGEventType, event: CGEvent) -> Self? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return make(type: type, keyCode: keyCode, modifierFlags: flags)
    }
}

/// The Fn / 右 Option global key listener.
///
/// Phase 2: the CGEventTap runs on its **own RunLoop thread**, so a busy main thread can no longer
/// delay the callback into a `kCGEventTapDisabledByTimeout` (the "Fn silently stops working until I
/// restart the app" bug). Because the callback no longer runs on the main actor, it can't reach the
/// `@MainActor` `FnChordStateMachine` to decide swallow — so the **swallow decision** is made
/// synchronously on the tap thread by `FnSwallowDecider` (anchor windows + a precomputed letter set
/// + a locked combo table), and the event is then hopped to the MainActor action handler in order.
/// See ADR-0035 for the 400ms-window decision and the known boundary edge.
///
/// `@unchecked Sendable`: fields are partitioned by thread and that partition is enforced by
/// convention (documented per field), not by the compiler.
final class NativeHotkeyEventTap: @unchecked Sendable {
    /// Action handler — runs on the MainActor, drives the state machines / recording classifier.
    typealias ActionHandler = @MainActor (NativeHotkeyEvent) -> Void

    private let log: Logger
    private let chordWindow: TimeInterval

    // MARK: Lifecycle / MainActor-only
    private var tap: CFMachPort?
    private var runLoopThread: Thread?
    private var watchdogTimer: Timer?
    private var isRestarting = false
    private let watchdogInterval: TimeInterval = 1.0
    /// Upper bound (seconds of idle) past which the watchdog STOPS posting its synthetic probe.
    /// The probe is a real HID event that resets the system idle timer — if posted forever it would
    /// keep the display from ever sleeping (HITL-confirmed 2026-06-30). Beyond this the user has
    /// walked away, so a probe isn't worth blocking display sleep; a death is still caught the moment
    /// idle re-enters the [interval, ceiling] window. Must stay well below the display-sleep setting.
    private let probeIdleCeiling: TimeInterval = 10.0
    /// A liveness probe posted last tick is awaiting its round-trip (MainActor-only watchdog state).
    private var probePending = false
    /// How many times the watchdog has rebuilt the tap this session (field diagnostic).
    private var sessionRestartCount = 0
    /// One-shot guard so a revoked-permission rebuild loop prompts the user once, not every tick.
    private var didPromptForAccessibility = false
    /// Sentinel keyCode for the watchdog's injected probe — not a real key, so it can't collide with
    /// a genuine press. The callback recognises it, marks it received, and eats it.
    private let watchdogProbeKeyCode: CGKeyCode = 0xFFFF
    /// Set once before events flow; read only on the MainActor (inside `hopToAction`'s main hop).
    private var actionHandler: ActionHandler?

    // MARK: Tap-thread-only swallow state — touched ONLY inside `decideSwallow` / `resetSwallowState`
    private var decider = FnSwallowDecider()
    private var rightOptionAnchorActive = false
    private var fnWindowOpenedAt: TimeInterval = 0
    private var rightOptionWindowOpenedAt: TimeInterval = 0
    /// Set once by the tap thread at startup, read by `stop()` on the MainActor to tear the loop
    /// down. `CFRunLoopStop` is thread-safe; the write/read are separated by the thread's lifetime.
    nonisolated(unsafe) private var threadRunLoop: CFRunLoop?

    // MARK: Cross-thread shared (lock-protected) — written by MainActor, read by the tap thread
    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private struct Shared: Sendable {
        var comboMatchTable: [UInt16: [Int]] = [:]
        var recording = false
        /// Set by the callback when the watchdog's sentinel probe round-trips (proves the tap is
        /// still delivering events even when `tapIsEnabled` lies). Read+reset by the watchdog.
        var mockReceived = false
        /// Monotonic time of the last *real* event the callback saw. Lets the watchdog skip its
        /// synthetic probe while genuine events are flowing (zero overhead + no idle disturbance
        /// during active use).
        var lastRealEventAt: TimeInterval = 0
    }

    init(
        log: Logger = Logger(subsystem: AppBrand.loggerSubsystem, category: "native-hotkey"),
        chordWindow: TimeInterval = 0.4
    ) {
        self.log = log
        self.chordWindow = chordWindow
    }

    var isRunning: Bool { tap != nil }

    /// The MainActor action handler. Set before `start()`.
    @MainActor func setActionHandler(_ handler: @escaping ActionHandler) {
        actionHandler = handler
    }

    @MainActor func setComboMatchTable(_ table: [UInt16: [Int]]) {
        shared.withLock { $0.comboMatchTable = table }
    }

    @MainActor func setRecording(_ recording: Bool) {
        shared.withLock { $0.recording = recording }
    }

    // MARK: - Lifecycle

    @discardableResult
    @MainActor func start() -> Bool {
        guard tap == nil else { return true }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let createdTap = Self.createEventTap(userInfo: selfPtr) else {
            log.warning("Native hotkey CGEventTap failed")
            return false
        }

        tap = createdTap
        let thread = Thread { [weak self] in self?.runTapThread(createdTap) }
        thread.name = "com.responsay.eventtap"
        thread.start()
        runLoopThread = thread

        startWatchdog()
        log.info("Native hotkey CGEventTap started on dedicated thread")
        return true
    }

    /// Creates the tap in a `nonisolated` context so the C callback closure does NOT inherit the
    /// caller's `@MainActor` isolation — otherwise it traps with an executor assertion when it fires
    /// on the dedicated thread (off the main actor). This is the Phase-2 crash fix.
    nonisolated private static func createEventTap(userInfo: UnsafeMutableRawPointer) -> CFMachPort? {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                NativeHotkeyEventTap.eventTapCallback(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: userInfo)
    }

    /// Runs on the dedicated thread: bind the tap source to *this* thread's run loop and spin it.
    private func runTapThread(_ tap: CFMachPort) {
        resetSwallowState()
        let runLoop = CFRunLoopGetCurrent()
        threadRunLoop = runLoop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()  // returns when stop() calls CFRunLoopStop
        if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
    }

    private func resetSwallowState() {
        decider = FnSwallowDecider()
        rightOptionAnchorActive = false
        fnWindowOpenedAt = 0
        rightOptionWindowOpenedAt = 0
    }

    @MainActor func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = threadRunLoop { CFRunLoopStop(runLoop) }  // CFRunLoopStop is thread-safe
        threadRunLoop = nil
        tap = nil
        runLoopThread = nil
    }

    // MARK: - Watchdog (Phase 1, retained)

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: watchdogInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
    }

    /// Active liveness check (Typeless's `watcherResults` mechanism, ADR-0035 follow-up). Each tick:
    /// (1) re-enable a system-disabled tap cheaply; (2) confirm last tick's sentinel probe came back
    /// — if it didn't, the tap is "enabled but silently dead", so rebuild; (3) if no real event has
    /// flowed for a full interval, post a fresh probe. Probing is skipped while real events flow, so
    /// it adds nothing during active use.
    @MainActor private func watchdogTick() {
        guard let tap, !isRestarting else { return }

        if !CGEvent.tapIsEnabled(tap: tap) {
            log.warning("Native hotkey CGEventTap disabled — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        let (received, lastReal) = shared.withLock { state -> (Bool, TimeInterval) in
            let r = state.mockReceived
            state.mockReceived = false
            return (r, state.lastRealEventAt)
        }

        if probePending && !received {
            probePending = false
            log.warning("Watchdog probe not received — tap silently dead, rebuilding")
            rebuild(reason: "watchdog-probe-timeout")
            return
        }
        probePending = false

        // Probe only inside a bounded idle window [interval, ceiling]:
        //  - below interval: real events are flowing, they already prove the tap is alive.
        //  - above ceiling: the user has walked away; the probe (a synthetic HID event) would reset
        //    the system idle timer and keep the display awake forever (HITL-confirmed), so we stop.
        // A genuine death is still caught: lastReal freezes at the death, idle re-enters the window
        // within one tick, the probe fires and fails → rebuild.
        let idle = Self.monotonicNow() - lastReal
        guard idle >= watchdogInterval, idle <= probeIdleCeiling else { return }

        probePending = true
        postWatchdogProbe()
    }

    /// Injects the sentinel key-down into the HID tap so a healthy tap echoes it back to the
    /// callback. A `.privateState` source keeps it off the shared HID state as much as possible.
    private func postWatchdogProbe() {
        guard let source = CGEventSource(stateID: .privateState),
              let probe = CGEvent(keyboardEventSource: source, virtualKey: watchdogProbeKeyCode, keyDown: true) else {
            return
        }
        probe.post(tap: .cghidEventTap)
    }

    /// Re-arm path for the system's own `tapDisabledBy*` callback: re-enable, rebuild if that fails.
    @MainActor private func recover() {
        guard let tap, !isRestarting else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) {
            log.info("Native hotkey CGEventTap re-enabled after system disable")
            return
        }
        log.warning("Re-enable did not take — rebuilding CGEventTap")
        rebuild(reason: "system-disable-reenable-failed")
    }

    @MainActor private func rebuild(reason: String) {
        guard !isRestarting else { return }
        isRestarting = true
        probePending = false
        sessionRestartCount += 1
        // Field diagnostic (Console: subsystem com.semanticcraft.responsay.mac category native-hotkey):
        // how often the watchdog had to rebuild, and why. A rising count on a machine = the dedicated
        // thread wasn't enough there.
        log.warning("CGEventTap rebuild #\(self.sessionRestartCount, privacy: .public) reason=\(reason, privacy: .public)")
        stop()
        let ok = start()
        isRestarting = false
        if ok {
            didPromptForAccessibility = false  // healthy again — re-arm the one-shot prompt
            return
        }
        log.error("CGEventTap rebuild failed (reason=\(reason, privacy: .public))")
        // A rebuild that can't recreate the tap is almost always revoked Accessibility / Input
        // Monitoring (tapCreate returns nil without it). Prompt once per revocation episode — not on
        // every 1s watchdog tick — so the user gets one actionable dialog instead of a storm.
        if !AccessibilityPermission.isTrusted, !didPromptForAccessibility {
            didPromptForAccessibility = true
            log.warning("Accessibility appears revoked — prompting the user")
            _ = AccessibilityPermission.promptIfNeeded()
        }
    }

    // MARK: - Swallow decision (tap thread)

    /// Decides whether to eat `event` so it never reaches the focused app. Pure w.r.t. injected
    /// `now`; mutates only tap-thread-confined swallow state. Exposed for tests via
    /// `decideSwallowForTesting`.
    private func decideSwallow(_ event: NativeHotkeyEvent, at now: TimeInterval) -> Bool {
        let (recording, comboTable) = shared.withLock { state -> (Bool, [UInt16: [Int]]) in
            state.lastRealEventAt = now  // a real event proves the tap is alive (watchdog skips probing)
            return (state.recording, state.comboMatchTable)
        }

        switch event {
        case let .flagsChanged(keyCode, modifierFlags):
            if !recording {
                updateAnchorWindows(keyCode: keyCode, modifierFlags: modifierFlags, at: now)
            }
            return false  // a modifier change is never swallowed
        case let .keyDown(keyCode, modifierFlags):
            if recording { return true }  // recording a shortcut: eat every key
            expireWindows(at: now)
            let pressed = ComboHotkeyMatcher.carbonModifiers(from: modifierFlags)
            let comboMatch = comboTable[keyCode]?.contains(pressed) ?? false
            return decider.keyDown(keyCode: keyCode, comboMatch: comboMatch)
        case let .keyUp(keyCode):
            if recording { return true }
            return decider.keyUp(keyCode: keyCode)
        }
    }

    private func updateAnchorWindows(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, at now: TimeInterval) {
        switch FnFlagsRouter.route(keyCode: keyCode, modifierFlags: modifierFlags, rightOptionIsActive: rightOptionAnchorActive) {
        case .anchorDown(.fn, _):
            decider.setFnWindow(open: true)
            fnWindowOpenedAt = now
        case .anchorUp(.fn):
            decider.setFnWindow(open: false)
        case .anchorDown(.rightOption, _):
            rightOptionAnchorActive = true
            decider.setRightOptionWindow(open: true)
            rightOptionWindowOpenedAt = now
        case .anchorUp(.rightOption):
            rightOptionAnchorActive = false
            decider.setRightOptionWindow(open: false)
        case .modifiersChanged, .ignore:
            break
        }
    }

    /// Lazily closes a chord window that has outlived the 400ms tap window (ADR-0035: time-check
    /// expiry instead of a cross-thread timer).
    private func expireWindows(at now: TimeInterval) {
        if decider.fnWindowOpen, now - fnWindowOpenedAt >= chordWindow {
            decider.setFnWindow(open: false)
        }
        if decider.rightOptionWindowOpen, now - rightOptionWindowOpenedAt >= chordWindow {
            decider.setRightOptionWindow(open: false)
        }
    }

    private func hopToAction(_ event: NativeHotkeyEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.actionHandler?(event) }
        }
    }

    private static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Testing hook

    @discardableResult
    func decideSwallowForTesting(_ event: NativeHotkeyEvent, at now: TimeInterval) -> Bool {
        decideSwallow(event, at: now)
    }

    // MARK: - C callback

    nonisolated private static func eventTapCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let refcon {
                let eventTap = Unmanaged<NativeHotkeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { eventTap.recover() } }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let refcon else { return Unmanaged.passUnretained(event) }
        let eventTap = Unmanaged<NativeHotkeyEventTap>.fromOpaque(refcon).takeUnretainedValue()

        // Watchdog liveness probe round-tripped: mark it received and eat it so the sentinel never
        // reaches an app or the action handler.
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == eventTap.watchdogProbeKeyCode, type == .keyDown || type == .keyUp {
            eventTap.shared.withLock { $0.mockReceived = true }
            return nil
        }

        // Pass through key events this app itself posted (text insertion / ⌘V / ⌘C). Without this
        // the tap would combo-match its own synthetic output and could swallow a paste/copy that
        // collides with a user-defined ⌘/⌃ combo (macOS LLKHF_INJECTED equivalent — research report
        // 优化点 #2). Done before `decideSwallow` so our output also doesn't count as a "real event"
        // for the watchdog's idle tracking.
        if SyntheticEventTag.isOurs(event) {
            return Unmanaged.passUnretained(event)
        }

        guard let nativeEvent = NativeHotkeyEvent.make(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let shouldSwallow = eventTap.decideSwallow(nativeEvent, at: monotonicNow())
        eventTap.hopToAction(nativeEvent)
        return shouldSwallow ? nil : Unmanaged.passUnretained(event)
    }
}
