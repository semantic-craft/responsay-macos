import Foundation

/// The single source of truth for the dictation「思考中」sub-phase word (issue 523).
///
/// The capsule shows a distinct label per real pipeline stage — 识别中 (snap OCR),
/// 转写中 (during `speech.stop()`: audio upload + ASR), 整理中 (during the LLM polish).
/// Transitions are driven by real events (`snapRecognizing` / `isFinalizingTranscript`
/// on `QuickCaptureViewModel`), never a timer. Both capsule surfaces (pill + notch)
/// map through this one function so their wording can't drift apart.
public enum DictationProgressLabel {
    /// `intentCompiling` (558): the Intent-aware Dictate mode shows its own compile/verify word
    /// so the user always knows the experiment — not ordinary 整理 — is producing this result.
    public static func label(finalizing: Bool, snapRecognizing: Bool, intentCompiling: Bool = false) -> String {
        if snapRecognizing { return "识别中" }
        if finalizing { return "转写中" }
        return intentCompiling ? "校验成稿中（实验）" : "整理中"
    }
}
