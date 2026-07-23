import Testing
import Foundation
@testable import ResponsayCore

/// 2026-06-16 — 轻度润色 runs on the bundled light_polish skill. The marker is a phrase
/// unique to the light_polish skill body, proving the actual skill (not just the assembler
/// base) is in.
struct PolishTidySkillTests {
    private let marker = "结合上下文语义主动推断"

    @Test func bundledSkillBodyResolvesFromTheBundle() {
        #expect(PolishTidySkill.body?.contains(marker) == true)
        #expect(PolishTidySkill.steeringSection().contains(marker))
    }

    @Test func batchPolishPromptInjectsTheSkill() {
        let p = PolishPromptBuilder.build(text: "你好 那个 我想说")
        #expect(p.system.contains(marker))
        #expect(p.system.contains("\"text\""))   // batch JSON envelope still authoritative
    }

    @Test func batchPolishKeepsStyleHintAlongsideTheSkill() {
        let p = PolishPromptBuilder.build(text: "你好", styleHint: "用公文体。")
        #expect(p.system.contains(marker))          // skill present
        #expect(p.system.contains("用公文体。"))      // active-pack nudge still appended
    }

}
