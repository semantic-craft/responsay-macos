import Foundation
import ResponsayCore

/// Drives 任意提问 (Ask Anything) from a hotkey with the same tap-to-run lifetime as dictation: one
/// tap starts a hands-free session and the next tap stops it. Hold-only is reserved for selection
/// interaction, which injects `.holdOnly` through `gestureProvider`.
///
/// The pure gesture decision (`TapHoldGestureClassifier`) and single-owner gate
/// (`HoldTriggerOwnership`) are the same primitives `CaptureSpeechController` uses; only this thin
/// orchestration is parallel. `startSession` / `stopSession` are injected so the tap/hold routing
/// is unit-tested without a live VM, mic, or LLM. `startSession` is where the controller's owner
/// grabs the current selection and grounds the question on it.
@MainActor
final class CaptureAskAnythingController {
    private let isListening: @MainActor () -> Bool
    private let startSession: @MainActor () -> Void
    private let stopSession: @MainActor () -> Void
    private let gestureProvider: @MainActor () -> TriggerGesture
    private let now: () -> TimeInterval

    /// Only the trigger that began the session may end it (a foreign / stale key-up can't cut a
    /// newer capture short) — same gate dictation uses (HOTKEY-MODE-001).
    private var holdOwnership = HoldTriggerOwnership()
    /// When each still-held trigger was pressed, so an injected hold-only controller can classify
    /// the release while ordinary hotkeys ignore it.
    private var pressDownAt: [String: TimeInterval] = [:]

    init(
        isListening: @escaping @MainActor () -> Bool,
        startSession: @escaping @MainActor () -> Void,
        stopSession: @escaping @MainActor () -> Void,
        gestureProvider: @escaping @MainActor () -> TriggerGesture = { TriggerStyleSettings.gesture(for: .askAnything) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.isListening = isListening
        self.startSession = startSession
        self.stopSession = stopSession
        self.gestureProvider = gestureProvider
        self.now = now
    }

    /// Press edge: begin a session unless one is already listening, in which case this press is the
    /// second tap that stops the hands-free session.
    func handleDown(trigger: HotkeyTrigger) {
        switch TapHoldGestureClassifier.onDown(isListening: isListening()) {
        case .begin:
            holdOwnership.acquire(trigger)
            pressDownAt[trigger.id] = now()
            startSession()
        case .stopHandsFree:
            pressDownAt[trigger.id] = nil
            _ = holdOwnership.release(trigger)
            stopSession()
        case .stopPushToTalk, .ignore:
            break
        }
    }

    /// Release edge: ordinary hotkeys ignore release; selection interaction may inject hold-only
    /// so release submits. A foreign or stale key-up is a no-op.
    func handleUp(trigger: HotkeyTrigger) {
        let downAt = pressDownAt.removeValue(forKey: trigger.id)
        let heldFor = downAt.map { now() - $0 } ?? 0
        let decision = TapHoldGestureClassifier.onUp(
            gesture: gestureProvider(),
            heldFor: heldFor,
            isListening: isListening(),
            ownsSession: holdOwnership.owner == trigger)
        _ = holdOwnership.release(trigger)
        if decision == .stopPushToTalk {
            stopSession()
        }
    }
}
