import Foundation

// 375 (feedback slice) — the teaching DECISIONS (which CaptureResult, which review
// outcome) live in `CaptureTransformer`. 写入并讲解 is express → insert immediately →
// open the coach card. (The former second prosody-analyze pass was retired with the
// prosody visualization.) This extension just sets transcript, guards empty, applies.
extension QuickCaptureViewModel {
    func processTeachingFeedback(_ text: String) async {
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        switch await transformer.teachingExpress(text, using: coach, locale: locale) {
        case let .expressed(capture, review):
            // Insert the idiomatic text now (low latency), then open the coach card.
            captureResult = capture
            do {
                try await CaptureResultInserter.insertIfNeeded(capture, using: inserter)
            } catch {
                enterError(error.localizedDescription)
                return
            }
            didAutoInsertResult = true
            await apply(review)
        case let .failed(reason):
            enterError(reason)
        }
    }
}
