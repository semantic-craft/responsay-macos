import Testing
import Foundation
@testable import ResponsayCore

/// 220 — EnabledLegalSkillStore: which legal skills are enabled in the ⌥L palette.
/// Pure resolve (default vs explicit) + a UserDefaults-backed instance the Settings
/// toggles + onboarding write to. nil (never set) → 6 built-in defaults; [] (user
/// turned everything off) → empty, distinct from default.
struct EnabledLegalSkillStoreTests {

    // MARK: pure resolve

    @Test func resolve_whenUnset_returnsTheDefaultBuiltins() {
        let ids = EnabledLegalSkillStore.resolve(stored: nil)
        #expect(ids == EnabledLegalSkillStore.defaultEnabledIDs)
        #expect(ids.count == 7)   // 5 → 4 after retiring 案情分析与诉讼策略, → 5 with 思路推演, → 6 with 提示词优化, → 7 with 目标七问
    }

    @Test func resolve_emptyStored_meansAllDisabled_notDefault() {
        #expect(EnabledLegalSkillStore.resolve(stored: []) == [])
    }

    @Test func resolve_storedIDs_roundTrip() {
        #expect(EnabledLegalSkillStore.resolve(stored: ["a.cn", "b.cn"]) == ["a.cn", "b.cn"])
    }

    // MARK: UserDefaults-backed

    private func freshStore(_ name: String) -> (EnabledLegalSkillStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (EnabledLegalSkillStore(defaults: defaults), defaults)
    }

    @Test func store_defaultsWhenUnset() {
        let (store, _) = freshStore("test.enabled.default")
        #expect(store.enabledIDs == EnabledLegalSkillStore.defaultEnabledIDs)
    }

    @Test func store_setEnabledFalse_persistsAcrossInstances() {
        let (store, defaults) = freshStore("test.enabled.persist")
        let target = "verification.fact_check.cn"
        store.setEnabled(false, id: target)
        let reopened = EnabledLegalSkillStore(defaults: defaults)
        #expect(!reopened.isEnabled(target))
        #expect(reopened.isEnabled("academic.counterargument.cn"))
    }

    @Test func store_ensureEnabled_addsForcedOnboardingSkill() {
        let (store, _) = freshStore("test.enabled.ensure")
        let forced = "practice.case_strategy.cn"
        store.setEnabled(false, id: forced)
        store.ensureEnabled(forced)
        #expect(store.isEnabled(forced))
    }
}
