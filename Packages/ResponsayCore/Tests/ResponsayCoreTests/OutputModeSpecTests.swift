import Foundation
import Testing
@testable import ResponsayCore

// The deepened `OutputMode`: every per-mode fact (ASR profile, whether a text model
// is required, translate fidelity) lives on one descriptor — `OutputMode.spec` — instead
// of being re-derived by switches scattered across the capture pipeline.

@Test func outputModeSpec_coachRewrite_isFaithfulAndNeedsTextModel() {
    let spec = QuickCaptureViewModel.OutputMode.coachRewrite.spec
    #expect(spec.asrProfile == .faithful)
    #expect(spec.requiresTextModel == true)
}

@Test func outputModeSpec_intentAware_preservesControlCuesWithoutUsingPolishPreflight() {
    let spec = QuickCaptureViewModel.OutputMode.intentAwareDictation.spec
    #expect(spec.asrProfile == .faithful)
    #expect(spec.requiresTextModel == false)
    #expect(spec.translateStyle == nil)
}

// `.translate` used to mean two things by input. Split into two modes so the fidelity is a
// fixed fact of the mode, not a guess at the call site. 听写翻译 (spoken) → most natural
// phrasing of the intent; 选区翻译 (written) → faithful, literal rendering.
@Test func outputModeSpec_translateSplit_pinsFidelityToTheMode() {
    let spoken = QuickCaptureViewModel.OutputMode.translateSpoken.spec
    #expect(spoken.translateStyle == .nativeIntent)
    #expect(spoken.asrProfile == .faithful)
    #expect(spoken.requiresTextModel == true)

    let written = QuickCaptureViewModel.OutputMode.translateWritten.spec
    #expect(written.translateStyle == .literal)

    // Non-translate modes carry no translate fidelity.
    #expect(QuickCaptureViewModel.OutputMode.coachRewrite.spec.translateStyle == nil)
}
