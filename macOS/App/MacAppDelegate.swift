import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.showSettingsWindow()
        }
        return false
    }

    var captureControllerStartAction: (() -> Void)?
    /// Set by `ResponsayMacApp`, used only for an orderly teardown on quit
    /// (UPDATE-ACTIVE-CAPTURE-003). Weak so the delegate never extends its lifetime.
    weak var captureController: CaptureController?
    /// Capture must start exactly once per process — completed / deferred-close /
    /// repair-mode paths can all race to start it (issue 313).
    private var captureStarted = false

    private func startCaptureOnce() {
        guard !captureStarted else { return }
        captureStarted = true
        captureControllerStartAction?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        let underTest = false
        #endif
        // INSTANCE-DOUBLE-001: hand off to the already-running instance and quit rather than
        // register a second set of global hotkeys / mic engine.
        if !underTest, SingleInstanceGuard.terminateIfDuplicate() { return }

        // 退役 provider（智谱）遗留的选择与钥匙串密钥一次性清理；带完成标记，正常只跑一次。
        if !underTest { RetiredProviderCleanup.run() }

        // #55: persistent Qwen ASR Context is opt-in and privacy-bounded. Enforce its two-hour
        // expiry at real application startup; when the switch is off, remove any stale store.
        if !underTest { PersistentASRContextSettings.prepareAtLaunch() }

        // LOGIN-ITEM-001: re-register the login item if the stored "开机自启" pref says ON but
        // macOS dropped the registration (happens on every app-bundle replace). Without this,
        // the toggle shows ON forever while launch-at-login silently never fires.
        if !underTest { LoginItemManager.reconcileAtLaunch() }

        // Enforce retention only after the duplicate-instance gate. Capture history and the
        // correction ledger use the same boundary; the in-memory ASR Context is not involved.
        if !underTest {
            _ = CaptureHistoryStoreFactory.make()
            HistoryRetentionCleanup.pruneLearningRecords()
        }

        AutoLearnHotwordNotificationPresenter.shared.start()

        // 2026-06-29: one-time — strip the legacy built-in example terms (CLSCI / SSRN / …) that
        // earlier builds folded into the dictionary. We no longer ship default hotwords.
        ContextHotwordSettings.removeSeededDefaultsIfNeeded()

        NotificationCenter.default.addObserver(forName: .onboardingCompleted, object: nil, queue: .main) { [weak self] _ in
            self?.startCaptureOnce()
        }
        // 313: closing the wizard mid-way = "稍后完成" — the app runs with whatever
        // permissions exist instead of a dead session; menu bar offers re-entry.
        NotificationCenter.default.addObserver(forName: .onboardingDeferred, object: nil, queue: .main) { [weak self] _ in
            self?.startCaptureOnce()
        }

        let forceOnboarding = ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey)
        let hasAccessibility = AccessibilityPermission.isTrusted
        let hasMicrophone = MicrophonePermission.isGranted
        let hasCorePermissions = hasAccessibility && hasMicrophone

        if forceOnboarding || !hasCompletedOnboarding {
            OnboardingWindowController.shared.show()
        } else if !hasCorePermissions {
            // 313: a revoked permission after a completed onboarding used to relaunch
            // the FULL 9-step wizard (saved step was cleared on completion). Now: the
            // single permissions-repair pane, and capture starts anyway — degraded
            // beats dead.
            OnboardingWindowController.shared.showPermissionsRepair()
            startCaptureOnce()
        } else {
            startCaptureOnce()
        }
    }

    /// UPDATE-ACTIVE-CAPTURE-003: tear down a live capture before quitting / Sparkle relaunch
    /// so the mic is released and no stale insertion survives. Only `.listening` holds the mic;
    /// once `.thinking`, the engine is already stopped so an immediate quit is safe.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let vm = captureController?.vm, vm.phase == .listening else {
            return .terminateNow
        }
        Task { @MainActor in
            await vm.cancelCapture()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    static func showSettingsWindow() {
        MacSettingsWindowController.shared.show()
    }
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}
