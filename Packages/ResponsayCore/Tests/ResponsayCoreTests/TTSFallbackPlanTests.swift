import Testing
@testable import ResponsayCore

/// #391 — always-usable TTS chain decision: selected → Kokoro (if installed) → system.
@Suite struct TTSFallbackPlanTests {
    @Test func selectedReadyUsesSelected() {
        #expect(TTSFallbackPlan.target(selectedReady: true, kokoroInstalled: false) == .selected)
        #expect(TTSFallbackPlan.target(selectedReady: true, kokoroInstalled: true) == .selected)
    }

    @Test func notReadyFallsBackToKokoroWhenInstalled() {
        #expect(TTSFallbackPlan.target(selectedReady: false, kokoroInstalled: true) == .kokoro)
    }

    @Test func notReadyWithoutKokoroFallsBackToSystem() {
        #expect(TTSFallbackPlan.target(selectedReady: false, kokoroInstalled: false) == .system)
    }

    @Test func runtimeFailureLadderTriesSelectedKokoroThenSystem() {
        #expect(TTSFallbackPlan.runtimeTargets(selectedIsKokoro: false) == [.selected, .kokoro, .system])
    }

    @Test func kokoroSelectionDoesNotTryKokoroTwice() {
        #expect(TTSFallbackPlan.runtimeTargets(selectedIsKokoro: true) == [.kokoro, .system])
    }
}
