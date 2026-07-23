import Foundation
import Testing
@testable import ResponsayCore

/// #560 — a verified result only inserts when it can still prove it's the original target; any
/// drift (app / window / editability / vanished / no start identity) falls back to a safe copy,
/// never a guess into whatever gained focus.
struct TargetBindingEvaluatorTests {
    private func snap(
        bundle: String? = "com.apple.TextEdit",
        pid: Int32? = 100,
        window: String? = "Untitled",
        editable: Bool = true
    ) -> InsertionTargetSnapshot {
        InsertionTargetSnapshot(bundleID: bundle, processID: pid, windowTitle: window, isEditable: editable)
    }

    @Test func unchangedTargetInserts() {
        #expect(TargetBindingEvaluator.decide(start: snap(), current: snap()) == .insert)
    }

    @Test func differentAppFallsBackToSafeCopy() {
        let now = snap(bundle: "com.google.Chrome", pid: 200)
        #expect(TargetBindingEvaluator.decide(start: snap(), current: now) == .safeCopy(.appChanged))
    }

    @Test func sameBundleDifferentProcessIsAppChanged() {
        // A relaunch keeps the bundle id but gets a new pid — a different instance.
        let now = snap(pid: 999)
        #expect(TargetBindingEvaluator.decide(start: snap(pid: 100), current: now) == .safeCopy(.appChanged))
    }

    @Test func differentWindowInSameAppIsWindowChanged() {
        let now = snap(window: "Другой документ")
        #expect(TargetBindingEvaluator.decide(start: snap(window: "Untitled"), current: now)
            == .safeCopy(.windowChanged))
    }

    @Test func unreadableWindowTitleIsNotTreatedAsDrift() {
        // A nil title on either side must not downgrade ordinary dictation to a copy.
        let start = snap(window: nil)
        let now = snap(window: "Anything")
        #expect(TargetBindingEvaluator.decide(start: start, current: now) == .insert)
        #expect(TargetBindingEvaluator.decide(start: snap(window: "X"), current: snap(window: nil)) == .insert)
    }

    @Test func nonEditableTargetFallsBackToSafeCopy() {
        let now = snap(editable: false)
        #expect(TargetBindingEvaluator.decide(start: snap(), current: now) == .safeCopy(.targetNotEditable))
    }

    @Test func vanishedTargetFallsBackToSafeCopy() {
        #expect(TargetBindingEvaluator.decide(start: snap(), current: nil) == .safeCopy(.targetVanished))
        let unreadable = InsertionTargetSnapshot(bundleID: nil, isEditable: false)
        #expect(TargetBindingEvaluator.decide(start: snap(), current: unreadable) == .safeCopy(.targetVanished))
    }

    @Test func noStartIdentityNeverGuessesALaterTarget() {
        #expect(TargetBindingEvaluator.decide(start: nil, current: snap()) == .safeCopy(.identityUnknown))
        let noBundleStart = InsertionTargetSnapshot(bundleID: nil, isEditable: false)
        #expect(TargetBindingEvaluator.decide(start: noBundleStart, current: snap()) == .safeCopy(.identityUnknown))
    }
}
