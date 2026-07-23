import Foundation
import Testing
@testable import ResponsayCore

/// #565 — the persistence + session-clearing contract for approved Intent-aware finals: only the
/// verified text + route + coarse outcome are stored (never the raw utterance), and every terminal
/// path drops the session's raw-bearing state while keeping the non-raw undo transaction / copy pill.
@MainActor
struct IntentHistoryPrivacyTests {
    private static func noIntentControlCompiler() -> FixtureIntentCompiler {
        FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .noIntentControl,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: []))
        }
    }

    private func snap(_ bundle: String) -> InsertionTargetSnapshot {
        InsertionTargetSnapshot(
            bundleID: bundle, processID: 1, windowTitle: "W", isEditable: true,
            selection: SelectionEvidence(selectedText: "旧选区"))
    }

    private func makeVM(
        transcript: String = "A",
        snapshots: [InsertionTargetSnapshot?]? = nil,
        isEditableTarget: (@MainActor () -> Bool)? = nil
    ) -> (QuickCaptureViewModel, MockTextInserter, FileCaptureStore) {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = transcript
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        var index = 0
        let provider: (@MainActor () -> InsertionTargetSnapshot?)?
        if let snapshots {
            provider = { defer { index += 1 }; return index < snapshots.count ? snapshots[index] : snapshots.last ?? nil }
        } else {
            provider = nil
        }
        let executor: (@MainActor (IntentUndoPlan) async -> Bool)?
        if provider == nil { executor = nil } else { executor = { _ in true } }
        let vm = QuickCaptureViewModel(
            speech: speech, coach: MockCoachAPI(), store: store, inserter: inserter,
            isEditableTarget: isEditableTarget,
            intentCompiler: Self.noIntentControlCompiler(),
            intentRoutePolicyProvider: { .injectedCompiler },
            intentTargetSnapshotProvider: provider,
            intentTargetTextProvider: { "前 A 后" },
            intentUndoExecutor: executor)
        vm.locale = .chinese
        return (vm, inserter, store)
    }

    @Test func intentInsert_persistsPrivacySafeFinalAndClearsSessionRaw() async throws {
        // Bound target unchanged across start + commit → a real insert, arming the undo transaction.
        let (vm, inserter, store) = makeVM(snapshots: [snap("com.a"), snap("com.a")])

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(inserter.inserted == ["A"])
        let saved = try #require(try store.recent(10).first)
        #expect(saved.sourceText == nil)                       // 原口述未保存
        #expect(saved.idiomatic == "A")
        #expect(saved.language == "zh-CN")
        #expect(saved.reasons.isEmpty)                         // no content-bearing change reason
        #expect(saved.intentRoute == .ordinaryPolished)
        #expect(saved.intentOutcome == .inserted)
        // Session raw / plan / evidence cleared…
        #expect(vm.transcript.isEmpty)
        #expect(vm.captureResult == nil)
        #expect(vm.intentReviewProposal == nil)
        #expect(vm.intentCaptureStartSnapshot == nil)
        // …but the non-raw undo transaction survives its window (verified text + prior selection).
        #expect(vm.intentInsertionTransaction?.insertedText == "A")
        #expect(vm.intentInsertionTransaction?.priorSelection?.selectedText == "旧选区")
    }

    @Test func intentTargetDrift_persistsCopiedOutcomeKeepsPillClearsRaw() async throws {
        // Frontmost app drifts between start and commit → one safe copy, persisted as `.copied`.
        let (vm, inserter, store) = makeVM(snapshots: [snap("com.a"), snap("com.other")])

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(vm.phase == .copied)
        #expect(vm.copiedText == "A")                          // the copy pill text is kept
        #expect(inserter.inserted.isEmpty)
        let saved = try #require(try store.recent(10).first)
        #expect(saved.sourceText == nil)
        #expect(saved.idiomatic == "A")
        #expect(saved.intentOutcome == .copied)
        #expect(vm.captureResult == nil)                       // raw sourceTranscript cleared
        #expect(vm.transcript.isEmpty)
        #expect(vm.intentInsertionTransaction == nil)          // nothing written into a document to undo
    }

    @Test func intentNoEditableTarget_persistsCopiedOutcome() async throws {
        // No editable field at all → the result routes to a copy pill, persisted as `.copied`.
        let (vm, inserter, store) = makeVM(isEditableTarget: { false })

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(vm.phase == .copied)
        #expect(vm.copiedText == "A")
        #expect(inserter.inserted.isEmpty)
        let saved = try #require(try store.recent(10).first)
        #expect(saved.sourceText == nil)
        #expect(saved.intentOutcome == .copied)
        #expect(vm.transcript.isEmpty)
        #expect(vm.captureResult == nil)
    }
}
