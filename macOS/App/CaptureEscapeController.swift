import Foundation

/// Routes Esc during capture-like listening states. Esc is cancellation, not submit:
/// ordinary dictation discards audio; 任意提问 drops the current question audio without
/// sending it to the LLM.
@MainActor
final class CaptureEscapeController {
    private let isCaptureListening: @MainActor () -> Bool
    private let cancelCapture: @MainActor () async -> Void
    private let isAskAnythingListening: @MainActor () -> Bool
    private let cancelAskAnything: @MainActor () async -> Void

    init(
        isCaptureListening: @escaping @MainActor () -> Bool,
        cancelCapture: @escaping @MainActor () async -> Void,
        isAskAnythingListening: @escaping @MainActor () -> Bool,
        cancelAskAnything: @escaping @MainActor () async -> Void
    ) {
        self.isCaptureListening = isCaptureListening
        self.cancelCapture = cancelCapture
        self.isAskAnythingListening = isAskAnythingListening
        self.cancelAskAnything = cancelAskAnything
    }

    func handleEscape() async {
        if isCaptureListening() {
            await cancelCapture()
            return
        }
        if isAskAnythingListening() {
            await cancelAskAnything()
        }
    }
}
