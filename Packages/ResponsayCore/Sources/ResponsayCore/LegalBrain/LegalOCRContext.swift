import Foundation

// MARK: - 111 Explicit OCR-assisted legal context
//
// When Accessibility can't read text in the focused app (Chrome / Electron / 飞书),
// the user may EXPLICITLY capture the region via OCR so a legal skill still has input.
// Hard rule (ADR-0012/0021): OCR is never an automatic AX fallback — the panel offers a
// labeled "OCR 选区取文" action the user taps. This core decides *whether to offer* it
// and bridges OCR text into the **built** `LegalContextPayload` (source = .ocr); it does
// NOT run OCR (that is issue 070's on-device Apple Vision + ScreenCaptureKit provider) and
// it does not fork the payload (no `primaryText` / parallel source enum).

public enum LegalOCRContext {
    /// Whether to OFFER the explicit OCR action. True only when Accessibility yielded no
    /// usable text — so OCR is a user choice on an AX-blind app, never a silent fallback.
    public static func shouldOfferOCR(axText: String?) -> Bool {
        (axText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true
    }

    /// Bridge user-invoked OCR text into a `LegalContextPayload`, labeled `source = .ocr`
    /// so prompts and UI know it is OCR-derived (possibly noisy; no cursor/selection
    /// structure). Returns nil if the OCR text is empty.
    public static func payload(
        fromOCRText text: String,
        scene: LegalScene,
        stage: LegalStage,
        appName: String,
        windowTitleHash: String? = nil
    ) -> LegalContextPayload? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return LegalContextPayload(
            selectedText: cleaned,
            scene: scene,
            stage: stage,
            appName: appName,
            windowTitleHash: windowTitleHash,
            contextScope: .selectedTextOnly,   // OCR gives no selection structure
            source: .ocr)
    }
}
