import Foundation
import Testing
@testable import ResponsayCore

/// #568 — the VM half of the warm-cloud latency trace: a live speech capture that reaches a
/// verified insert emits exactly one sample with the `stop`/`visible` boundaries filled in; a
/// non-insert terminal (needs-review) emits none. The sink is the app's on-device observation
/// point for the real-Mac latency run — this proves the plumbing end to end, headless.
@MainActor
private final class IntentLatencySampleBox {
    var samples: [IntentLatencyTrace] = []
}

@MainActor
private func makeLatencyVM(
    compiler: any IntentPlanCompiler,
    transcript: String,
    box: IntentLatencySampleBox
) -> (vm: QuickCaptureViewModel, inserter: MockTextInserter) {
    let speech = MockSpeechCaptureService()
    speech.transcriptToReturn = transcript
    let inserter = MockTextInserter()
    let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        intentCompiler: compiler,
        intentRoutePolicyProvider: { .injectedCompiler },
        intentLatencySink: { box.samples.append($0) })
    return (vm, inserter)
}

@Test @MainActor func intentAwareInsert_emitsOneWarmSampleWithStopToVisible() async throws {
    let box = IntentLatencySampleBox()
    let compiler = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        let plan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1]))
            ])
        return try JSONEncoder().encode(plan)
    }
    let (vm, inserter) = makeLatencyVM(
        compiler: compiler, transcript: "周三开会，不对，周四开会", box: box)

    vm.push(outputMode: .intentAwareDictation)
    await vm.release()

    #expect(vm.phase == .idle)
    #expect(inserter.inserted == ["周四开会"])
    #expect(box.samples.count == 1)
    let sample = try #require(box.samples.first)
    // The full stop→visible span is present, and every non-skippable safety stage was stamped.
    #expect(sample.marks[.stop] != nil)
    #expect(sample.marks[.compile] != nil)
    #expect(sample.marks[.planVerify] != nil)
    #expect(sample.marks[.sourceRender] != nil)
    #expect(sample.marks[.postRenderGuard] != nil)
    #expect(sample.marks[.visible] != nil)
    #expect(sample.safetyStagesPresent)
    let total = try #require(sample.stopToVisibleMs)
    #expect(total >= 0)
    // The in-flight stop boundary is cleared once the terminal insert completes (no stale reuse).
    #expect(vm.intentLatencyStopMark == nil)
}

@Test @MainActor func intentAwareNeedsReview_emitsNoWarmSample() async throws {
    let box = IntentLatencySampleBox()
    let needsReviewJSON = #"{"version":1,"decision":"needsReview","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#
    let (vm, inserter) = makeLatencyVM(
        compiler: FixtureIntentCompiler { _ in Data(needsReviewJSON.utf8) },
        transcript: "A", box: box)

    vm.push(outputMode: .intentAwareDictation)
    await vm.release()

    #expect(vm.phase == .review)
    #expect(inserter.inserted.isEmpty)
    #expect(box.samples.isEmpty)   // review is not a warm stop→visible sample
}
