import AppKit
import OSLog
import ResponsayCore

@MainActor
final class CaptureSpeechController {
    private let vm: QuickCaptureViewModel
    private let targetTracker: TargetAppTracker
    private let log: Logger
    private let textModelPreflight: @MainActor (QuickCaptureViewModel.OutputMode) -> Bool
    private let soundPlayer = InteractionSoundPlayer.shared
    /// Electron targets need their AX tree switched on before the stop-time editable-focus gate
    /// can see the field; requested at capture start so it builds while the user speaks.
    private let axUnlock = ElectronAXUnlock()
    /// Owns the current press session. Only the trigger that started it may release ownership, so
    /// a different binding's (or a stale gesture's) key-up can't cut a newer capture short.
    private var holdOwnership = HoldTriggerOwnership()
    /// Per-trigger record of the in-flight press. Ordinary voice hotkeys are tap-only, but the
    /// release edge still needs to release ownership and ignore stale key-up events safely.
    private var activePresses: [String: (action: ShortcutAction, downAt: TimeInterval)] = [:]

    init(
        vm: QuickCaptureViewModel,
        targetTracker: TargetAppTracker,
        log: Logger,
        textModelPreflight: @escaping @MainActor (QuickCaptureViewModel.OutputMode) -> Bool = { _ in true }
    ) {
        self.vm = vm
        self.targetTracker = targetTracker
        self.log = log
        self.textModelPreflight = textModelPreflight
        AudioOutputMuter.shared.recoverStuckMuteIfNeeded()
        startMuteObservation()
    }

    // MARK: - Mute other audio while the mic is live

    /// Invariant: the output device is muted iff (phase == .listening && the user
    /// enabled it). Driving this off `phase` covers every exit — user stop, auto
    /// finalize, or error — so the system can't get stuck muted.
    private func startMuteObservation() {
        withObservationTracking {
            _ = vm.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncMuteWithPhase()
                self.startMuteObservation()   // re-arm (one-shot)
            }
        }
    }

    private func syncMuteWithPhase() {
        if vm.phase == .listening, muteWhileRecordingEnabled {
            // Delay so the start cue (≤0.48s) is heard before output goes silent.
            AudioOutputMuter.shared.engage(afterDelay: startSoundEnabled ? 0.6 : 0)
        } else {
            AudioOutputMuter.shared.disengage()
        }
    }

    private var muteWhileRecordingEnabled: Bool {
        UserDefaults.standard.object(forKey: "muteWhileRecording") as? Bool ?? true
    }

    // Always forward key-up to the controller so it can release ownership. Ordinary Fn / right
    // Option actions are tap-only; selection interaction owns the hold-only path separately.
    var isHoldToTalkEnabled: Bool { true }

    func trigger() {
        triggerRewrite()
    }

    func triggerRaw() {
        trigger(outputMode: .rawTranscript)
    }

    func triggerPolished() {
        trigger(outputMode: .polishedTranscript)
    }

    func triggerExpressInEnglish() {
        trigger(outputMode: .teachingFeedback)
    }

    func triggerRewrite() {
        trigger(outputMode: .coachRewrite)
    }

    func triggerTeaching() {
        trigger(outputMode: .teachingFeedback)
    }

    func beginCaptureFromHotkey(_ action: ShortcutAction, trigger: HotkeyTrigger) {
        guard let outputMode = Self.outputMode(forAction: action) else {
            return
        }

        handleKeyDown(action: action, outputMode: outputMode, trigger: trigger)
    }

    func finishCurrentHotkeyAction(trigger: HotkeyTrigger) {
        handleKeyUp(trigger: trigger)
    }

    private func trigger(outputMode: QuickCaptureViewModel.OutputMode) {
        log.info("Capture trigger requested; phase \(String(describing: self.vm.phase), privacy: .public); ASR \(ASREngine.selected.rawValue, privacy: .public); mode \(String(describing: outputMode), privacy: .public)")
        let starting = (vm.phase == .idle || vm.phase == .review || vm.phase == .error)
        let stopping = (vm.phase == .listening)
        if starting, (!textModelPreflight(outputMode) || !prepareStart()) { return }
        if stopping { playConfiguredStopCue() }
        Task {
            await vm.toggle(outputMode: outputMode)
            if starting { playStartCueIfListening() }
        }
    }

    private static func outputMode(forAction action: ShortcutAction) -> QuickCaptureViewModel.OutputMode? {
        switch action {
        case .raw:
            // Default 轻度改写 (clean polish); routes to 如实 verbatim only when 「如实输入」 is on.
            // See `DictationRewriteSettings` (the menu toggle + settings selector share it).
            DictationRewriteSettings.dictationOutputMode()
        case .translate:
            .translateSpoken
        case .polish:
            .polishedTranscript
        case .expressInEnglish:
            // 地道外文: the 「输出方式」 setting picks one of two card modes —— 写入并讲解
            // (teachingFeedback) / 仅讲解 (coachRewrite). The former 直接写入 (no-card insert) was
            // merged into 听写翻译 / Fn+Shift (nativeIntent translate).
            ExpressInsertSettings.mode().outputMode
        case .rewriteSelection, .translateSelection, .snapOCR, .snapTextOCR, .snapImageCopy,
             .selectionMenu, .readAloudSelection, .askAnything, .openApp, .openSettings, .confirmInsert:
            nil
        }
    }

    /// Press edge: a down begins a tap-to-run session, unless one is already listening — then the
    /// press is the second tap that stops it. We still stamp ownership so release edges from stale
    /// or foreign triggers cannot affect the live session.
    private func handleKeyDown(
        action: ShortcutAction,
        outputMode: QuickCaptureViewModel.OutputMode,
        trigger: HotkeyTrigger
    ) {
        switch TapHoldGestureClassifier.onDown(isListening: vm.phase == .listening) {
        case .begin:
            guard textModelPreflight(outputMode), prepareStart() else { return }
            holdOwnership.acquire(trigger)   // provisional: a held release may stop it
            activePresses[trigger.id] = (action, ProcessInfo.processInfo.systemUptime)
            vm.push(outputMode: outputMode)
            playStartCueIfListening()
        case .stopHandsFree:
            // A second tap stops the hands-free session this anchor left running.
            activePresses[trigger.id] = nil
            _ = holdOwnership.release(trigger)
            playConfiguredStopCue()
            Task { await vm.release() }
        case .stopPushToTalk, .ignore:
            break
        }
    }

    /// Release edge: ordinary hotkeys ignore release for capture lifetime and stop only on the next
    /// tap. The release still relinquishes provisional ownership; a foreign / stale key-up is a
    /// no-op.
    private func handleKeyUp(trigger: HotkeyTrigger) {
        let press = activePresses.removeValue(forKey: trigger.id)
        let heldFor = press.map { ProcessInfo.processInfo.systemUptime - $0.downAt } ?? 0
        let gestureOverride = press.map { TriggerStyleSettings.gesture(for: $0.action) } ?? .tapOnly
        let decision = TapHoldGestureClassifier.onUp(
            gesture: gestureOverride,
            heldFor: heldFor,
            isListening: vm.phase == .listening,
            ownsSession: holdOwnership.owner == trigger)
        _ = holdOwnership.release(trigger)   // relinquish our claim (no-op if foreign)
        if decision == .stopPushToTalk {
            playConfiguredStopCue()
            Task { await vm.release() }
        }
    }

    @discardableResult
    private func prepareStart() -> Bool {
        targetTracker.capture()
        axUnlock.request(for: targetTracker.target)
        guard MicrophonePermission.promptIfNeeded() else { return false }
        applyLocalePreference()
        return true
    }

    func playStartCue() {
        soundPlayer.playCaptureStart()
    }

    func playStopCue() {
        soundPlayer.playCaptureStop()
    }

    func playConfiguredStartCue() {
        guard startSoundEnabled else { return }
        playStartCue()
    }

    func playConfiguredStopCue() {
        // Restore output before the cue (phase is still .listening here, so the
        // observer hasn't unmuted yet) so the stop cue is actually audible.
        AudioOutputMuter.shared.disengage()
        guard startSoundEnabled else { return }
        playStopCue()
    }

    private func playStartCueIfListening() {
        guard vm.phase == .listening else { return }
        playConfiguredStartCue()
    }

    private func applyLocalePreference() {
        if let raw = UserDefaults.standard.string(forKey: "defaultLocale"),
           let locale = CaptureLocale(rawValue: raw) {
            vm.locale = locale
        }
    }

    private var startSoundEnabled: Bool {
        UserDefaults.standard.object(forKey: "startSound") as? Bool ?? true
    }
}
