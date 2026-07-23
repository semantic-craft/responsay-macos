import Testing
import Foundation
@testable import ResponsayCore

/// `CaptureTaskSet` owns `QuickCaptureViewModel`'s six background `Task` handles behind
/// `set` / `cancel` / `cancelAll`, collapsing the repeated `xTask?.cancel(); xTask = nil` idiom.
/// The caller keeps its own reference to the stored `Task`, so `Task.cancel()` — which flips
/// `isCancelled` synchronously — is asserted directly without any sleep/timing race.
@Suite @MainActor struct CaptureTaskSetTests {
    /// A task the harness can observe: it never resolves on its own, so its only route to
    /// `isCancelled == true` is a `CaptureTaskSet` cancellation.
    private func neverEndingTask() -> Task<Void, Never> {
        Task { try? await Task.sleep(nanoseconds: .max) }
    }

    @Test func setThenCancelAllCancelsTheStoredTask() {
        let set = CaptureTaskSet()
        let task = neverEndingTask()
        set.set(.level, task)
        set.cancelAll()
        #expect(task.isCancelled)
    }

    @Test func cancelAllCancelsEverySlot() {
        let set = CaptureTaskSet()
        let level = neverEndingTask()
        let partial = neverEndingTask()
        let failsafe = neverEndingTask()
        set.set(.level, level)
        set.set(.partial, partial)
        set.set(.failsafe, failsafe)
        set.cancelAll()
        #expect(level.isCancelled)
        #expect(partial.isCancelled)
        #expect(failsafe.isCancelled)
    }

    @Test func settingTheSameSlotTwiceCancelsThePriorHandleOnly() {
        let set = CaptureTaskSet()
        let first = neverEndingTask()
        let second = neverEndingTask()
        set.set(.errorDismiss, first)
        set.set(.errorDismiss, second)  // replaces `first` in the slot
        #expect(first.isCancelled)
        #expect(!second.isCancelled)
    }

    @Test func cancelSlotCancelsOnlyThatSlot() {
        let set = CaptureTaskSet()
        let revert = neverEndingTask()
        let correction = neverEndingTask()
        set.set(.revertExpiry, revert)
        set.set(.correctionExpiry, correction)
        set.cancel(.revertExpiry)
        #expect(revert.isCancelled)
        #expect(!correction.isCancelled)
    }
}
