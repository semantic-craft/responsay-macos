import Testing
@testable import ResponsayCore

struct DictationProgressLabelTests {
    @Test func snapRecognizing_showsRecognizing() {
        #expect(DictationProgressLabel.label(finalizing: false, snapRecognizing: true) == "识别中")
    }

    @Test func finalizing_showsTranscribing() {
        #expect(DictationProgressLabel.label(finalizing: true, snapRecognizing: false) == "转写中")
    }

    @Test func neither_showsPolishing() {
        #expect(DictationProgressLabel.label(finalizing: false, snapRecognizing: false) == "整理中")
    }

    @Test func snapRecognizing_winsOverFinalizing() {
        // Snap OCR recognizing takes precedence over the dictation finalizing flag,
        // matching CapsuleView's existing if-order.
        #expect(DictationProgressLabel.label(finalizing: true, snapRecognizing: true) == "识别中")
    }

    @Test func pipelineSequence_recognizeThenPolish() {
        // The real dictation pipeline: finalizing=true during speech.stop() (upload+ASR),
        // then false while the LLM polishes. The label sequence must be 转写中 → 整理中.
        let stages: [(finalizing: Bool, snap: Bool)] = [(true, false), (false, false)]
        let labels = stages.map { DictationProgressLabel.label(finalizing: $0.finalizing, snapRecognizing: $0.snap) }
        #expect(labels == ["转写中", "整理中"])
    }
}
