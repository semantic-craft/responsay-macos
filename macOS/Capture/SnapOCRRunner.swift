import CoreGraphics
import Foundation
import ResponsayCore

// MARK: - 070 Snap & Translate · testable orchestration core
//
// The branch logic of Snap & Translate, pulled out of `CaptureController.snapOCR()` so the capture
// mechanism and OCR engine are injected as seams (`ScreenRegionCapturer` / `OCRProvider`). That
// makes "capture → recognize → classify" unit-testable without a screen, a permission grant, or the
// full controller — and it finally puts the `ScreenRegionCapturer` seam to work (injection), not
// just on paper. The controller becomes a thin mapper from outcome → view-model. Screen-recording
// permission stays in the controller (a system side effect) so this stays pure.

enum SnapOCROutcome: Equatable {
    /// User cancelled the region select (Esc) or capture failed — caller stays idle.
    case cancelled
    /// Captured and recognized non-empty text. Carries the full `OCRResult` (regions included) so the
    /// 截图取字 panel can smart-paragraph; the translate path just reads `.text`.
    case recognized(OCRResult)
    /// Captured, but OCR found no text — caller shows guidance.
    case empty
    /// OCR threw — caller surfaces the message.
    case failed(String)
}

struct SnapOCRRunner {
    private let capturer: ScreenRegionCapturer
    private let provider: any OCRProvider
    private let fallbackProvider: (any OCRProvider)?

    init(
        capturer: ScreenRegionCapturer = SystemScreenRegionCapturer(),
        provider: any OCRProvider = AppleVisionOCRProvider(),
        fallbackProvider: (any OCRProvider)? = AppleVisionOCRProvider()
    ) {
        self.capturer = capturer
        self.provider = provider
        self.fallbackProvider = fallbackProvider
    }

    /// `onRecognizing` fires once the region is captured and the (possibly network-bound) recognize is
    /// about to start — the seam Snap & Translate uses to show a "识别中…" spinner during a cloud
    /// round-trip. It never fires on a cancelled capture (Esc), so the caller only enters its
    /// recognizing state when there is real work to wait on. Defaults to a no-op (on-device / tests).
    /// `onCaptured` fires once the region is captured, handing the caller the source `CGImage` — the
    /// 截图取字 panel keeps it to re-OCR with another engine and to show "看原图" without re-selecting.
    /// It never fires on a cancelled capture (Esc). Defaults to a no-op (translate path / tests).
    func run(
        onCaptured: @MainActor (CGImage) -> Void = { _ in },
        onRecognizing: @MainActor () -> Void = {}
    ) async -> SnapOCROutcome {
        guard let image = await capturer.captureRegion() else { return .cancelled }
        await onCaptured(image)
        await onRecognizing()
        do {
            let result = try await provider.recognize(image)
            if isUseful(result) { return .recognized(result) }
            if let fallback = fallbackProvider, fallback.id != provider.id {
                let fallbackResult = try await fallback.recognize(image)
                return isUseful(fallbackResult) ? .recognized(fallbackResult) : .empty
            }
            return .empty
        } catch {
            if let fallback = fallbackProvider, fallback.id != provider.id,
               let fallbackResult = try? await fallback.recognize(image), isUseful(fallbackResult) {
                return .recognized(fallbackResult)
            }
            return .failed(error.localizedDescription)
        }
    }

    private func isUseful(_ result: OCRResult) -> Bool {
        result.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
}
