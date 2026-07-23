import Testing
import Foundation
@testable import ResponsayCore

/// The 划词菜单 activation contract: 翻译 / 朗读 / 加入词典 / 任意提问 are fixed; 引注源验 /
/// 来源辅助检索 / 规范排版 appear only when their backing 技能平台 skill / 工具 is 激活.
struct SelectionMenuGateTests {
    private let fixed: [SelectionAction] = [.translate, .readAloud, .addToDictionary, .ask]
    private let verifySkill = "verification.fact_check.cn"
    private let searchSkill = "research.search_strategy.cn"

    @Test func fixedFunctionsAlwaysAvailable_evenWithNothingEnabled() {
        let gate = SelectionMenuGate(enabledSkillIDs: [], enabledTools: [])
        for action in fixed {
            #expect(gate.isAvailable(action))
        }
    }

    @Test func skillGatedActionsFollowTheirSkill() {
        let onlyVerify = SelectionMenuGate(enabledSkillIDs: [verifySkill], enabledTools: [])
        #expect(onlyVerify.isAvailable(.verify))
        #expect(onlyVerify.isAvailable(.assistedSearch) == false)

        let onlySearch = SelectionMenuGate(enabledSkillIDs: [searchSkill], enabledTools: [])
        #expect(onlySearch.isAvailable(.assistedSearch))
        #expect(onlySearch.isAvailable(.verify) == false)
    }

    @Test func toolGatedActionFollowsTool() {
        let toolOff = SelectionMenuGate(enabledSkillIDs: [], enabledTools: [])
        #expect(toolOff.isAvailable(.normalizeTypography) == false)

        let toolOn = SelectionMenuGate(enabledSkillIDs: [], enabledTools: [.normalizeTypography])
        #expect(toolOn.isAvailable(.normalizeTypography))
    }

    @Test func availableFromPreservesOrderAndDropsGatedOff() {
        // Everything the resolver hands over, in canonical order, with only the fixed set enabled.
        let all: [SelectionAction] = [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask, .addToDictionary]
        let gate = SelectionMenuGate(enabledSkillIDs: [], enabledTools: [])
        #expect(gate.available(from: all) == [.translate, .readAloud, .ask, .addToDictionary])
    }

    @Test func allEnabled_keepsFullSet() {
        let all: [SelectionAction] = [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask, .addToDictionary]
        let gate = SelectionMenuGate(
            enabledSkillIDs: [verifySkill, searchSkill],
            enabledTools: [.normalizeTypography])
        #expect(gate.available(from: all) == all)
    }

    // MARK: - EnabledSelectionToolStore default-ON semantics

    @Test func toolStoreDefaultsEnabled_thenTogglesOffAndBack() {
        let suite = "SelectionMenuGateTests.tools"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = EnabledSelectionToolStore(defaults: defaults)

        // Never set → enabled, so upgraders keep 规范排版 without a migration.
        #expect(store.isEnabled(.normalizeTypography))
        #expect(store.enabledTools == [.normalizeTypography])

        store.setEnabled(false, tool: .normalizeTypography)
        #expect(store.isEnabled(.normalizeTypography) == false)
        #expect(store.enabledTools.isEmpty)

        store.setEnabled(true, tool: .normalizeTypography)
        #expect(store.isEnabled(.normalizeTypography))

        defaults.removePersistentDomain(forName: suite)
    }
}
