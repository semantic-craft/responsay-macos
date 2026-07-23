import Testing
@testable import ResponsayCore

/// 111 — explicit OCR-assisted legal context: offer policy + payload bridge + privacy.
struct LegalOCRContextTests {
    private let privacy = LegalPrivacyPolicy()

    // MARK: - Offer policy (never automatic)

    @Test func offersOCR_onlyWhenAXYieldsNoText() {
        #expect(LegalOCRContext.shouldOfferOCR(axText: nil) == true)
        #expect(LegalOCRContext.shouldOfferOCR(axText: "   \n ") == true)
        #expect(LegalOCRContext.shouldOfferOCR(axText: "被告应承担违约责任") == false)
    }

    // MARK: - Payload bridge (reuses the built type; source = .ocr)

    @Test func payload_labelsSourceOCR_noFork() {
        let payload = LegalOCRContext.payload(
            fromOCRText: "  本案标的额 120 万元。 ", scene: .litigation, stage: .evidenceReview,
            appName: "Electron")
        #expect(payload?.source == .ocr)
        #expect(payload?.contextScope == .selectedTextOnly)
        #expect(payload?.selectedText == "本案标的额 120 万元。")   // trimmed
        #expect(payload?.scene == .litigation)
    }

    @Test func payload_nilForEmptyOCR() {
        #expect(LegalOCRContext.payload(fromOCRText: "   ", scene: .privacy, stage: .piaTriage, appName: "x") == nil)
    }

    // MARK: - 110 privacy (2026-06-25 反转): OCR 取文不再被强制本地 / 阻断,route 只跟随用户偏好

    @Test func ocrSource_cloudFirst_stillGoesCloud() {
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", source: .ocr, modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)         // OCR 不再降级为"需确认"
    }

    @Test func ocrSource_localFirst_staysLocal() {
        // 用户显式选本地仍然本地。
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", source: .ocr, modelPreference: .localFirst)
        #expect(d.route == .localOnly)
    }

    @Test func accessibilitySource_unchangedRegression() {
        let d = privacy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func ocrSecureField_notBlocked() {
        // 安全输入框不再阻断;OCR + 默认 askEachTime → 发送前确认(由用户决定)。
        let d = privacy.decide(gate: .denied(.secureTextField), selectedText: "x", source: .ocr)
        #expect(d.route == .cloudRequiresUserConfirm)
        #expect(!d.isBlocked)
    }
}
