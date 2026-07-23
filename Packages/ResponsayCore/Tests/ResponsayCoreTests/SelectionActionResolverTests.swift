import Testing
import Foundation
@testable import ResponsayCore

/// 127 / 划词菜单 redesign — selection action routing. Verification: the fixed
/// instant-tools + legal-research set, term-only dictionary, empty → nothing,
/// and that the dropped actions (改写/地道表达/法律技能) never appear.
struct SelectionActionResolverTests {
    private let resolver = SelectionActionResolver()
    private let classifier = SelectionClassifier()

    private func scene(_ s: LegalScene) -> SceneStageClassification {
        SceneStageClassification(scene: s, stage: .briefDrafting, confidence: 0.8, reasons: [], shouldAskUser: false)
    }

    /// The smart row is fixed: every non-empty selection offers translate / readAloud /
    /// verify / assistedSearch / ask, regardless of language or scene.
    @Test func anySelection_offersFixedSet() {
        for text in ["I want to know if you can finish this by tomorrow.",
                     "被告应承担违约责任", "你好"] {
            let actions = resolver.actions(classification: classifier.classify(text))
            for expected: SelectionAction in [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask] {
                #expect(actions.contains(expected))
            }
        }
    }

    /// scene no longer changes the set — the explicit legal entries replaced the
    /// scene-gated 法律技能 palette.
    @Test func sceneDoesNotChangeSmartRow() {
        let c = classifier.classify("依据《民法典》第五百条……")
        let withScene = resolver.actions(classification: c, scene: scene(.litigation))
        let withoutScene = resolver.actions(classification: c, scene: nil)
        #expect(withScene == withoutScene)
    }

    // 300: a term-shaped fragment (专名/术语) offers「加入词典」; digits/symbols
    // alone (no letters) and full sentences do not.
    @Test func termFragment_offersDictionaryChip() {
        #expect(resolver.actions(classification: classifier.classify("Responsay")).contains(.addToDictionary))
        #expect(resolver.actions(classification: classifier.classify("北大法宝")).contains(.addToDictionary))
        #expect(resolver.actions(classification: classifier.classify("12345")).contains(.addToDictionary) == false)
        let sentence = classifier.classify("I want to know if you can finish this by tomorrow.")
        #expect(resolver.actions(classification: sentence).contains(.addToDictionary) == false)
    }

    @Test func chineseFragment_exactSet() {
        let actions = resolver.actions(classification: classifier.classify("你好"), scene: scene(.unknown))
        #expect(actions == [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask, .addToDictionary])
    }

    @Test func emptySelection_noActions() {
        let c = classifier.classify("")
        #expect(resolver.actions(classification: c, hasSelection: false).isEmpty)
    }

    /// The dropped actions must never surface (改写 → 任意提问; 地道表达 / 法律技能 retired).
    @Test func droppedActionsNeverAppear() {
        let cases = ["被告应承担违约责任",
                     "The defendant shall bear liability for the breach of contract.",
                     "Responsay"]
        let dropped: Set<String> = ["polish", "coachIdiomatic", "legalSkill"]
        for text in cases {
            let raws = Set(resolver.actions(classification: classifier.classify(text)).map(\.rawValue))
            #expect(raws.isDisjoint(with: dropped))
        }
    }

    @Test func autoInsertActionsReplaceSelectionInPlace() {
        // 翻译 + 规范排版 就地替换选区；其余开面板 / 来源 / 会话，不自动插入。
        #expect(SelectionAction.translate.autoInserts)
        #expect(SelectionAction.normalizeTypography.autoInserts)
        for action in [SelectionAction.verify, .assistedSearch, .readAloud, .addToDictionary, .ask] {
            #expect(action.autoInserts == false)
        }
    }

    // MARK: - verify — ungated, any selection can be verified

    @Test func anySelection_offersVerify() {
        #expect(resolver.actions(classification: classifier.classify("请帮我看看这段话通不通顺。")).contains(.verify))
        let cite = resolver.actions(classification: classifier.classify("《民法典》第五百条规定了缔约过失责任。"), scene: nil)
        #expect(cite.contains(.verify))
    }
}
