import Testing
import Foundation
@testable import ResponsayCore

/// 159 — dictionary scene presets (multi-select batch apply + hit stats).
struct DictionaryPresetCatalogTests {
    private let engine = DictionaryRuleEngine()

    @Test func builtInPresets_exist() {
        let names = DictionaryPresetCatalog.presets.map(\.name)
        #expect(names.contains("法律论文"))
        #expect(names.contains("数据法"))
        #expect(names.contains("英语学习"))
    }

    @Test func multiSelect_unionsRules_dedupingShared() {
        // legal.paper and data.law both reference the PIPL-typo rule.
        let enabled: Set<ScenePresetID> = [DictionaryPresetCatalog.legalPaperID, DictionaryPresetCatalog.dataLawID]
        let rules = DictionaryPresetCatalog.rules(forEnabledPresets: enabled)
        let ids = rules.map(\.id)
        #expect(Set(ids).count == ids.count)                       // no duplicate rule
        #expect(ids.contains(DictionaryPresetCatalog.idPiplTypo))  // shared rule present once
        #expect(ids.contains(DictionaryPresetCatalog.idDataLawTypo))
    }

    @Test func disabledPreset_rulesNotApplied() {
        let onlyEnglish: Set<ScenePresetID> = [DictionaryPresetCatalog.englishStudyID]
        let rules = DictionaryPresetCatalog.rules(forEnabledPresets: onlyEnglish)
        // 数据安全发 fix belongs to 数据法, which is NOT enabled → text unchanged.
        let result = engine.apply(to: "依据数据安全发第21条", rules: rules)
        #expect(result.corrected == "依据数据安全发第21条")
    }

    @Test func enabledPreset_appliesItsRules() {
        let enabled: Set<ScenePresetID> = [DictionaryPresetCatalog.dataLawID]
        let rules = DictionaryPresetCatalog.rules(forEnabledPresets: enabled)
        let result = engine.apply(to: "依据数据安全发第21条", rules: rules)
        #expect(result.corrected == "依据数据安全法第21条")
    }

    @Test func hitStats_aggregatePerPreset() {
        let enabled: Set<ScenePresetID> = [DictionaryPresetCatalog.legalPaperID, DictionaryPresetCatalog.dataLawID]
        let rules = DictionaryPresetCatalog.rules(forEnabledPresets: enabled)
        // article-spacing (legal.paper) hits once; 数据安全发 fix (data.law) hits once.
        let result = engine.apply(to: "第 12 条 与 数据安全发", rules: rules)
        let stats = DictionaryPresetCatalog.hitStats(result)
        #expect(stats[DictionaryPresetCatalog.legalPaperID] == 1)   // 第 12 条 normalized
        #expect(stats[DictionaryPresetCatalog.dataLawID] == 1)      // 数据安全发 → 法
        #expect(stats[DictionaryPresetCatalog.englishStudyID] == 0)
    }

    @Test func hotwords_unionFromSelectedPresets() {
        let enabled: Set<ScenePresetID> = [DictionaryPresetCatalog.dataLawID, DictionaryPresetCatalog.englishStudyID]
        let words = DictionaryPresetCatalog.hotwords(forEnabledPresets: enabled)
        #expect(words.contains("PIPL"))
        #expect(words.contains("arXiv"))
        #expect(Set(words).count == words.count)   // deduped
    }

    @Test func presetsDecodeAsScenePresets() throws {
        // Round-trip one preset through Codable (it's the built ScenePreset type).
        let preset = DictionaryPresetCatalog.preset(id: DictionaryPresetCatalog.legalPaperID)!
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(ScenePreset.self, from: data)
        #expect(decoded.name == "法律论文")
        #expect(decoded.hotwords.contains("CLSCI"))
    }
}
