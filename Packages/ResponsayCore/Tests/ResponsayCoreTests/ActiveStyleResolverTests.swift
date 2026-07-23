import Foundation
import Testing
@testable import ResponsayCore

// #2 — one resolver decides "which 日常办公 pack is active" once and derives BOTH the heavy-rewrite
// style and the 轻度润色 hint, with their distinct fallback rules side by side. Replaces the two
// drift-prone closures previously wired separately in CaptureController.

@Test func activeStyle_whenPackActive_bothOutputsUseIt() {
    let pack = StylePack(id: "style.formal.cn", name: "正式表达",
                         systemPrompt: "用正式书面语。", origin: .builtIn)
    let resolved = ActiveStyleResolver.resolve(
        availablePacks: [pack], activeID: "style.formal.cn", storedToneRaw: nil)
    #expect(resolved.heavyRewriteStyle == .pack(pack))
    #expect(resolved.polishHint == "用正式书面语。")
}

// Regression: with no everyday pack active, the heavy path falls back to the 表达升级 default,
// but 轻度润色 must NOT inherit it — polishHint stays nil (plain polish). The invariant that
// PolishStyleHintTests guards at the consumer, now pinned at the resolution.
@Test func activeStyle_noActivePack_polishNilWhileHeavyTakesUpgradeDefault() {
    let upgrade = StylePack(id: SkillCategorizer.expressionUpgradeSkillID, name: "表达升级",
                            systemPrompt: "自由重述，改得更重。", origin: .builtIn)
    let resolved = ActiveStyleResolver.resolve(
        availablePacks: [upgrade], activeID: nil, storedToneRaw: nil)
    #expect(resolved.heavyRewriteStyle == .pack(upgrade))
    #expect(resolved.polishHint == nil)
}

// A stored legacy 重改写风格 value (a RewriteTone rawValue) drives the heavy path when no pack is
// active; 轻度润色 stays plain.
@Test func activeStyle_noPackButStoredTone_heavyUsesToneAndPolishNil() {
    let resolved = ActiveStyleResolver.resolve(
        availablePacks: [], activeID: nil, storedToneRaw: RewriteTone.formal.rawValue)
    #expect(resolved.heavyRewriteStyle == .tone(.formal))
    #expect(resolved.polishHint == nil)
}

// A stored `pack:`-prefixed value resolves to that pack; an uninstalled one falls through to the
// 表达升级 default rather than crashing or going plain.
@Test func activeStyle_storedPackPrefix_resolvesOrFallsThrough() {
    let saved = StylePack(id: "style.structured.cn", name: "结构化",
                          systemPrompt: "分点输出。", origin: .builtIn)
    let upgrade = StylePack(id: SkillCategorizer.expressionUpgradeSkillID, name: "表达升级",
                            systemPrompt: "自由重述。", origin: .builtIn)

    let present = ActiveStyleResolver.resolve(
        availablePacks: [saved, upgrade], activeID: nil, storedToneRaw: "pack:style.structured.cn")
    #expect(present.heavyRewriteStyle == .pack(saved))

    let uninstalled = ActiveStyleResolver.resolve(
        availablePacks: [upgrade], activeID: nil, storedToneRaw: "pack:style.gone.cn")
    #expect(uninstalled.heavyRewriteStyle == .pack(upgrade))
}
