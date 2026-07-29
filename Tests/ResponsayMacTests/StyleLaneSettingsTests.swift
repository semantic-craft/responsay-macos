import XCTest
import ResponsayCore
@testable import ResponsayMac

final class StyleLaneSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "StyleLaneSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil; suiteName = nil
        super.tearDown()
    }

    func testDictationLaneUsesLegacyKey() {
        StyleLaneSettings.setActive("a", lane: .dictation, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "rewrite.activeEverydaySkillID"), "a")
        XCTAssertEqual(StyleLaneSettings.activeID(.dictation, defaults: defaults), "a")
    }

    /// 1.5.0 lane-pool split: the writing lane never seeds from dictation. A dictation choice —
    /// bundled OR imported — must never leak into 划词改写 (that cross-talk is what the split
    /// eliminates), so an untouched writing lane always reads nil (= built-in default).
    func testWritingLaneNeverSeedsFromDictation() {
        StyleLaneSettings.setActive("a", lane: .dictation, defaults: defaults)
        XCTAssertNil(StyleLaneSettings.activeID(.writing, defaults: defaults))
        StyleLaneSettings.setActive("b", lane: .writing, defaults: defaults)
        StyleLaneSettings.setActive("c", lane: .dictation, defaults: defaults)
        XCTAssertEqual(StyleLaneSettings.activeID(.writing, defaults: defaults), "b")
        XCTAssertEqual(StyleLaneSettings.activeID(.dictation, defaults: defaults), "c")
    }

    /// Installs from the seed era may hold the "" sentinel in the writing key — it must keep
    /// reading as "none", and clearing must work from that state.
    func testLegacyEmptySentinelReadsAsNone() {
        defaults.set("", forKey: "rewrite.activeWritingSkillID")
        XCTAssertNil(StyleLaneSettings.activeID(.writing, defaults: defaults))
        StyleLaneSettings.setActive(nil, lane: .writing, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "rewrite.activeWritingSkillID"))
    }

    private func pack(_ id: String) -> StylePack {
        StylePack(id: id, name: "风格 \(id)", systemPrompt: "把文字改成 \(id) 风格。", origin: .builtIn)
    }

    func testDictationAndWritingLanesResolveIndependently() {
        let dictPack = pack("style.dict")
        let writePack = pack("style.write")
        let packs = [dictPack, writePack]
        StyleLaneSettings.setActive(dictPack.id, lane: .dictation, defaults: defaults)
        StyleLaneSettings.setActive(writePack.id, lane: .writing, defaults: defaults)

        let dictation = RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: packs, defaults: defaults)
        let writing = RewriteStyleSettings.activeStyle(lane: .writing, availablePacks: packs, defaults: defaults)

        // Dictation polish comes from the dictation pack; writing heavy from the writing pack.
        XCTAssertEqual(dictation.polishHint, dictPack.systemPrompt)
        XCTAssertEqual(writing.heavyRewriteStyle, .pack(writePack))
        // No cross-talk: the two lanes never read each other's pack.
        XCTAssertEqual(dictation.heavyRewriteStyle, .pack(dictPack))
        XCTAssertEqual(writing.polishHint, writePack.systemPrompt)
        XCTAssertNotEqual(dictation.heavyRewriteStyle, writing.heavyRewriteStyle)
    }

    func testBuiltinStylePacksAreFunctionalOnDictationLane() {
        let packs = RewriteStyleSettings.availablePacks()
        for id in ["style.clear_structure.cn", "style.formal_expression.cn", "style.light_polish.cn"] {
            guard let p = packs.first(where: { $0.id == id }) else {
                XCTFail("内置风格包 \(id) 不在可用列表里"); continue
            }
            XCTAssertGreaterThan(p.systemPrompt.count, 40, "\(id) 提示词过短,疑似占位")
            StyleLaneSettings.setActive(id, lane: .dictation, defaults: defaults)
            let style = RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: packs, defaults: defaults)
            XCTAssertEqual(style.polishHint, p.systemPrompt, "激活 \(id) 后听写 polishHint 应是它的提示词")
        }
    }

    func testDictationDraftPresetsAreTheThreeRewriteSettingsChoices() {
        XCTAssertEqual(
            DictationDraftPreset.allCases.map(\.styleID),
            [nil, "style.clear_structure.cn", "style.formal_expression.cn"])
        XCTAssertEqual(
            DictationDraftPreset.allCases.map(\.title),
            ["智能整理", "清晰结构", "正式表达"])
    }

    func testDictationDraftPresetActivationUsesTheExistingDictationLane() {
        DictationDraftPreset.clearStructure.activate(defaults: defaults)
        XCTAssertEqual(StyleLaneSettings.activeID(.dictation, defaults: defaults), "style.clear_structure.cn")

        DictationDraftPreset.smartCleanup.activate(defaults: defaults)
        XCTAssertNil(StyleLaneSettings.activeID(.dictation, defaults: defaults))
    }

    func testLegacyLightPolishSelectionReadsAsSmartCleanup() {
        XCTAssertTrue(DictationDraftPreset.smartCleanup.matches(
            activeStyleID: SkillCategorizer.lightPolishSkillID))
        XCTAssertTrue(DictationDraftPreset.contains(
            styleID: SkillCategorizer.lightPolishSkillID))
    }
}
