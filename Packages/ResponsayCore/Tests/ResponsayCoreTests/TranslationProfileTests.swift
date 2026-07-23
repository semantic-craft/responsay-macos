import Testing
import Foundation
@testable import ResponsayCore

/// 142 — TranslationStyle × PromptProfile matrix.
/// Verification: style/profile resolution; legal `[待核]` preserved.
struct TranslationProfileTests {
    @Test func allStylesAndProfiles_present() {
        #expect(TranslationStyle.allCases.count == 4)   // balanced/faithful/polished/academic
        #expect(PromptProfile.allCases.count == 6)      // general/technical/academic/legal/subtitle/custom
    }

    @Test func temperature_isFixedLow() {
        #expect(TranslationProfileConfig().temperature == 0.2)
        #expect(TranslationProfileConfig.temperature == 0.2)
    }

    @Test func resolvesDirective_includesTargetStyleAndProfile() {
        let config = TranslationProfileConfig(style: .polished, profile: .technical, targetLanguage: "中文")
        let directive = config.resolvedDirective()
        #expect(directive.contains("中文"))
        #expect(directive.contains(TranslationStyle.polished.directive))
        #expect(directive.contains(PromptProfile.technical.directive))
    }

    @Test func customProfile_usesCustomDirective() {
        let config = TranslationProfileConfig(profile: .custom, customDirective: "保留品牌口吻")
        #expect(config.resolvedDirective().contains("保留品牌口吻"))
    }

    @Test func legalProfile_preservesPending() {
        let legal = TranslationProfileConfig(profile: .legal)
        #expect(legal.preservesPendingCoordinates)
        #expect(legal.resolvedDirective().contains("[待核]"))

        let general = TranslationProfileConfig(profile: .general)
        #expect(general.preservesPendingCoordinates == false)
        #expect(general.resolvedDirective().contains("[待核]") == false)
    }

    @Test func legalTranslationOutput_keepsNewCoordinatesPending() {
        // End-to-end discipline: a legal translation that emits a new statute
        // coordinate is re-marked [待核] by the shared guard.
        let config = TranslationProfileConfig(profile: .legal, targetLanguage: "中文")
        #expect(config.preservesPendingCoordinates)
        let anchors = NewCoordinateGuard().reconcile(text: "Per 《民法典》第577条, the party is liable.", existing: [])
        #expect(anchors.contains { $0.status == .pending })
    }
}
