import Foundation
import Testing
@testable import ResponsayCore

/// #560 — the verified Intent-aware result, driven through the VM: it inserts once into the bound
/// target and arms a safe undo; a drifted target degrades to one copy; undo deletes/restores or
/// refuses, never writes raw back, and is idempotent.
@MainActor
struct IntentInsertionTransactionOrchestrationTests {
    /// Returns queued snapshots in order (start snapshot first, then the pre-commit snapshot),
    /// holding the last value for any further reads.
    @MainActor final class SnapshotSource {
        var queue: [InsertionTargetSnapshot?]
        private var index = 0
        init(_ queue: [InsertionTargetSnapshot?]) { self.queue = queue }
        func next() -> InsertionTargetSnapshot? {
            defer { index += 1 }
            return index < queue.count ? queue[index] : queue.last ?? nil
        }
    }

    @MainActor final class RecordingUndoExecutor {
        var plans: [IntentUndoPlan] = []
        var result = true
        func run(_ plan: IntentUndoPlan) async -> Bool { plans.append(plan); return result }
    }

    private func snap(bundle: String, selection: String? = nil) -> InsertionTargetSnapshot {
        InsertionTargetSnapshot(
            bundleID: bundle, processID: 1, windowTitle: "W", isEditable: true,
            selection: selection.map(SelectionEvidence.init(selectedText:)))
    }

    private func makeVM(
        source: SnapshotSource,
        undo: RecordingUndoExecutor? = nil,
        targetText: String? = nil,
        transcript: String = "A"
    ) -> (QuickCaptureViewModel, MockTextInserter) {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = transcript
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        let compiler = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .noIntentControl,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: []))
        }
        let executor: (@MainActor (IntentUndoPlan) async -> Bool)?
        if let undo { executor = { await undo.run($0) } } else { executor = nil }
        let vm = QuickCaptureViewModel(
            speech: speech, coach: MockCoachAPI(), store: store, inserter: inserter,
            intentCompiler: compiler,
            intentRoutePolicyProvider: { .injectedCompiler },
            intentTargetSnapshotProvider: { source.next() },
            intentTargetTextProvider: { targetText },
            intentUndoExecutor: executor)
        return (vm, inserter)
    }

    @Test func boundTargetUnchangedInsertsOnceAndArmsUndo() async {
        let source = SnapshotSource([snap(bundle: "com.a", selection: "旧选区"), snap(bundle: "com.a", selection: "旧选区")])
        let undo = RecordingUndoExecutor()
        let (vm, inserter) = makeVM(source: source, undo: undo)

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["A"])
        #expect(vm.intentInsertionTransaction?.insertedText == "A")
        #expect(vm.intentInsertionTransaction?.priorSelection?.selectedText == "旧选区")
        #expect(vm.intentInsertionLifecycle?.state == .inserted)
        #expect(vm.revertableInsertion == nil)   // never the ↩原文 semantics
    }

    @Test func targetDriftDegradesToSafeCopyWithNoInsert() async {
        // Frontmost app changed between capture start and commit → safe copy, not a mis-insert.
        let source = SnapshotSource([snap(bundle: "com.a"), snap(bundle: "com.other")])
        let (vm, inserter) = makeVM(source: source)

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(vm.phase == .copied)
        #expect(vm.copiedText == "A")
        #expect(inserter.inserted.isEmpty)
        #expect(vm.intentInsertionTransaction == nil)
        #expect(vm.intentInsertionLifecycle?.state == .abandoned)
    }

    @Test func undoDeletesInsertedTextAndRecordsReverted() async {
        let source = SnapshotSource([snap(bundle: "com.a"), snap(bundle: "com.a")])
        let undo = RecordingUndoExecutor()
        let (vm, _) = makeVM(source: source, undo: undo, targetText: "前 A 后")

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        await vm.undoIntentInsertion()

        #expect(undo.plans == [.deleteInserted("A")])
        #expect(vm.intentInsertionTransaction == nil)
        #expect(vm.intentInsertionLifecycle?.state == .reverted)
    }

    @Test func undoRestoresPriorSelectionWhenOneWasReplaced() async {
        let source = SnapshotSource([snap(bundle: "com.a", selection: "原文"), snap(bundle: "com.a", selection: "原文")])
        let undo = RecordingUndoExecutor()
        let (vm, _) = makeVM(source: source, undo: undo, targetText: "开头 A 结尾")

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        await vm.undoIntentInsertion()

        #expect(undo.plans == [.restoreSelection(replacing: "A", with: "原文")])
        #expect(vm.intentInsertionLifecycle?.state == .reverted)
    }

    @Test func undoRefusesAndSkipsExecutorWhenFieldWasEditedPastTheInsert() async {
        let source = SnapshotSource([snap(bundle: "com.a"), snap(bundle: "com.a")])
        let undo = RecordingUndoExecutor()
        let (vm, _) = makeVM(source: source, undo: undo, targetText: "用户已经改成别的了")

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        await vm.undoIntentInsertion()

        #expect(undo.plans.isEmpty)                 // refuse never touches the document
        #expect(vm.intentInsertionLifecycle?.state == .abandoned)
    }

    @Test func doubleUndoOnlyRunsOnce() async {
        let source = SnapshotSource([snap(bundle: "com.a"), snap(bundle: "com.a")])
        let undo = RecordingUndoExecutor()
        let (vm, _) = makeVM(source: source, undo: undo, targetText: "前 A 后")

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        await vm.undoIntentInsertion()
        await vm.undoIntentInsertion()

        #expect(undo.plans.count == 1)              // the offer cleared after the first
    }
}
