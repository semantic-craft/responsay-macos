import Foundation

/// Owns `QuickCaptureViewModel`'s six background `Task` handles behind `set` / `cancel` / `cancelAll`,
/// collapsing the repeated `xTask?.cancel(); xTask = nil` idiom that was scattered across
/// `reset()` / `cancelCapture()` / `stopAndProcess()` and the offer/error sites.
///
/// A reference type held by the VM as a `let`, so the handles stay out of the VM's `@Observable`
/// tracking (the UI never reads them). The task *bodies* remain in the VM — only handle storage and
/// cancellation live here.
@MainActor
final class CaptureTaskSet {
    enum Slot { case level, partial, failsafe, errorDismiss, revertExpiry, correctionExpiry, intentUndoExpiry }

    private var tasks: [Slot: Task<Void, Never>] = [:]

    /// Store a task, cancelling any prior one in the same slot (matches the
    /// `xTask?.cancel(); xTask = Task { … }` idiom at the offer/error sites).
    func set(_ slot: Slot, _ task: Task<Void, Never>) {
        tasks[slot]?.cancel()
        tasks[slot] = task
    }

    /// Cancel + drop one slot (matches `xTask?.cancel(); xTask = nil`).
    func cancel(_ slot: Slot) {
        tasks[slot]?.cancel()
        tasks[slot] = nil
    }

    /// Cancel + drop every slot — the `reset()` invariant.
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
