import Testing
import Foundation
@testable import ResponsayCore

/// 158 — Dictionary wildcard engine.
/// Verification: Chinese numerals; Arabic numerals; case; legal-article citations.
struct DictionaryRuleEngineTests {
    private let engine = DictionaryRuleEngine()

    private func rule(
        _ pattern: String,
        _ replacement: String,
        _ type: DictionaryRuleType = .wildcardCorrection,
        id: UUID = UUID(),
        enabled: Bool = true
    ) -> DictionaryRule {
        DictionaryRule(id: id, pattern: pattern, replacement: replacement, ruleType: type, enabled: enabled)
    }

    // MARK: - {num}: Chinese + Arabic numerals

    @Test func wildcardNum_chineseNumeral_normalizesSpacing() {
        let r = rule("第 {num} 条", "第{num}条")
        let result = engine.apply(to: "依据 第 三 条 之规定", rules: [r])
        #expect(result.corrected == "依据 第三条 之规定")
        #expect(result.hitCount(for: r.id) == 1)
    }

    @Test func wildcardNum_arabicNumeral() {
        let r = rule("第 {num} 条", "第{num}条")
        let result = engine.apply(to: "见 第 12 条", rules: [r])
        #expect(result.corrected == "见 第12条")
    }

    @Test func wildcardNum_twoNumerals_两十() {
        let r = rule("第 {num} 条", "第{num}条")
        #expect(engine.apply(to: "第 两 条", rules: [r]).corrected == "第两条")
        #expect(engine.apply(to: "第 二十 条", rules: [r]).corrected == "第二十条")
    }

    @Test func wildcardNum_alreadyNormalized_noHit() {
        let r = rule("第 {num} 条", "第{num}条")
        let result = engine.apply(to: "第3条", rules: [r])
        #expect(result.corrected == "第3条")
        #expect(result.totalHits == 0)
    }

    // MARK: - {letter}: case / acronym spacing

    @Test func wildcardLetter_collapsesSpacedAcronym() {
        let r = rule("{letter} {letter} {letter} {letter}", "{letter}{letter}{letter}{letter}")
        let result = engine.apply(to: "依据 P I P L 第一章", rules: [r])
        #expect(result.corrected == "依据 PIPL 第一章")
    }

    // MARK: - Legal-article citation (exact correction + precision)

    @Test func exactCorrection_fixesTypo() {
        let r = rule("个人信息保护发", "个人信息保护法", .exactCorrection)
        let result = engine.apply(to: "依据个人信息保护发第十条", rules: [r])
        #expect(result.corrected == "依据个人信息保护法第十条")
        #expect(result.hitCount(for: r.id) == 1)
    }

    @Test func exactCorrection_doesNotFalseHitNeighbour() {
        // The 发→法 fix must not corrupt the correct term 北大法宝.
        let r = rule("个人信息保护发", "个人信息保护法", .exactCorrection)
        let result = engine.apply(to: "北大法宝 与 个人信息保护发", rules: [r])
        #expect(result.corrected == "北大法宝 与 个人信息保护法")
        #expect(result.corrected.contains("北大法宝"))
    }

    // MARK: - Hit counting

    @Test func hitCounting_countsEveryOccurrence_andBumpsRule() {
        let r = rule("色", "氏", .exactCorrection, id: UUID())
        let result = engine.apply(to: "色色色", rules: [r])
        #expect(result.hitCount(for: r.id) == 3)
        let bumped = result.applyingHits(to: [r], at: Date(timeIntervalSinceReferenceDate: 100))
        #expect(bumped[0].hitCount == 3)
        #expect(bumped[0].updatedAt == Date(timeIntervalSinceReferenceDate: 100))
    }

    // MARK: - Rollback for a false hit = disable + re-apply

    @Test func disablingRule_rollsBackItsCorrection() {
        let id = UUID()
        let good = rule("个人信息保护发", "个人信息保护法", .exactCorrection)
        // A poorly-scoped rule that false-hits 法宝 → 法律.
        let bad = rule("法宝", "法律", .exactCorrection, id: id)
        let original = "北大法宝 与 个人信息保护发"

        let withBad = engine.apply(to: original, rules: [good, bad])
        #expect(withBad.corrected == "北大法律 与 个人信息保护法")   // false hit present

        let disabled = DictionaryRule(
            id: bad.id, pattern: bad.pattern, replacement: bad.replacement,
            ruleType: bad.ruleType, enabled: false
        )
        let rolledBack = engine.apply(to: original, rules: [good, disabled])
        #expect(rolledBack.corrected == "北大法宝 与 个人信息保护法")  // only the good fix remains
    }

    // MARK: - Rule kinds the engine must ignore

    @Test func hotwordRule_isNotAppliedAsEdit() {
        let r = rule("Swift", "SWIFT", .hotword)
        let result = engine.apply(to: "I like Swift", rules: [r])
        #expect(result.corrected == "I like Swift")
        #expect(result.totalHits == 0)
    }

    @Test func disabledRule_isSkipped() {
        let r = rule("a", "b", .exactCorrection, enabled: false)
        #expect(engine.apply(to: "aaa", rules: [r]).corrected == "aaa")
    }

    // MARK: - regexCorrection

    @Test func regexCorrection_appliesTemplate() {
        let r = rule("\\bP\\.?I\\.?P\\.?L\\b", "PIPL", .regexCorrection)
        let result = engine.apply(to: "see P.I.P.L today", rules: [r])
        #expect(result.corrected == "see PIPL today")
    }
}
