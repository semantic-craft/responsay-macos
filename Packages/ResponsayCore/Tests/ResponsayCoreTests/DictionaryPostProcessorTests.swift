import Testing
import Foundation
@testable import ResponsayCore

/// 160 — apply dictionary rules in ASR post-processing.
/// Verification: partial vs final handling; log redaction.
struct DictionaryPostProcessorTests {
    private func makeProcessor() -> DictionaryPostProcessor {
        DictionaryPostProcessor(rules: [
            DictionaryRule(pattern: "个人信息保护发", replacement: "个人信息保护法", ruleType: .exactCorrection)
        ])
    }

    @Test func partial_isNeverForceCorrected() {
        let processor = makeProcessor()
        // Even though the partial contains the typo, partials stream through raw.
        #expect(processor.partial("依据个人信息保护发") == "依据个人信息保护发")
    }

    @Test func finalTranscript_hasRulesApplied() {
        let processor = makeProcessor()
        let result = processor.finalTranscript("依据个人信息保护发第十条")
        #expect(result.corrected == "依据个人信息保护法第十条")
    }

    @Test func finalTranscript_feedsCorrectedTextDownstream() {
        // The corrected string is what a caller would hand to the LLM.
        let processor = makeProcessor()
        let downstream = processor.finalTranscript("个人信息保护发").corrected
        #expect(downstream == "个人信息保护法")
    }

    @Test func redactedLog_omitsRawTranscript() {
        let processor = makeProcessor()
        let secret = "我的身份证号是个人信息保护发"
        let result = processor.finalTranscript(secret)
        let line = DictionaryPostProcessor.redactedLog(result)
        #expect(line.contains("hit"))
        #expect(line.contains("个人信息") == false)
        #expect(line.contains("身份证") == false)
        #expect(line == "dictionary: 1 hit(s) across 1 rule(s)")
    }

    @Test func noRules_isPassthrough() {
        let processor = DictionaryPostProcessor(rules: [])
        let result = processor.finalTranscript("anything at all")
        #expect(result.corrected == "anything at all")
        #expect(result.totalHits == 0)
    }
}
