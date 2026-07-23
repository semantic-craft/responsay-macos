import Testing
@testable import ResponsayCore

/// #427: the 地道英文 (express) `idiomatic` output is read aloud by TTS (讲解卡 🔊 + direct-write
/// → TTS), so the express prompt carries a speakability directive — plain text / no document
/// symbols / short, spoken-natural sentences. It must NOT leak into rewrite / polish / translate.
struct IdiomaticTTSReadabilityTests {
    @Test func expressPrompt_carriesTheSpeakabilityDirective() {
        let (system, _) = ExpressPromptBuilder.build(
            intent: "请你今天下午之前回复我", context: nil, register: .neutral)
        #expect(system.contains(TTSReadabilityDirective.speakable))
        #expect(system.contains("read aloud"))
        #expect(system.contains("No markdown"))
    }

    @Test func speakabilityDirective_constrainsAlternativesNotJustIdiomatic() {
        // #479: the 🔊 button reads `activeIdiomatic`, which becomes the *selected* alternative
        // when the user taps one — so alternatives are read aloud too and must follow the same
        // plain-spoken constraints, else a model-emitted "(parenthetical)" alternative gets spoken.
        #expect(TTSReadabilityDirective.speakable.contains("alternatives"))
        let (system, _) = ExpressPromptBuilder.build(
            intent: "请你今天下午之前回复我", context: nil, register: .neutral)
        #expect(system.contains(TTSReadabilityDirective.speakable))   // still injected into express
    }

    @Test func speakabilityDirective_doesNotLeakIntoRewritePolishOrTranslate() {
        // Range is strictly the English idiomatic output — these siblings are not read aloud,
        // or require faithful / structured presentation, so the directive must be absent.
        let others = [
            PolishPromptBuilder.build(text: "今天天气不错"),
            RewritePromptBuilder.build(text: "今天天气不错", tone: .natural),
            TranslatePromptBuilder.build(text: "今天天气不错", target: .englishUS),
        ]
        for (system, _) in others {
            #expect(!system.contains(TTSReadabilityDirective.speakable))
            #expect(!system.contains("Speakability"))
        }
    }
}
