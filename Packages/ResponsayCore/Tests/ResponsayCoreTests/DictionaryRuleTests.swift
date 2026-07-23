import Testing
import Foundation
@testable import ResponsayCore

/// 157 — Dictionary / hotword / correction rule schema.
/// Verification: schema decode; enabled/disabled toggle.
struct DictionaryRuleTests {
    @Test func decodes_minimalRule_usesDefaults() throws {
        let json = #"{"pattern":"个人信息保护发","replacement":"个人信息保护法"}"#.data(using: .utf8)!
        let rule = try JSONDecoder().decode(DictionaryRule.self, from: json)
        #expect(rule.ruleType == .exactCorrection)
        #expect(rule.enabled)
        #expect(rule.hitCount == 0)
        #expect(rule.scope == .any)
    }

    @Test func decodes_fullRule() throws {
        let json = """
        {"pattern":"第 {num} 条","replacement":"第{num}条","ruleType":"wildcardCorrection",
         "enabled":false,"hitCount":7,
         "scope":{"languages":["zh"],"scenes":["legal"],"appBundleIDs":["com.apple.TextEdit"]}}
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(DictionaryRule.self, from: json)
        #expect(rule.ruleType == .wildcardCorrection)
        #expect(rule.enabled == false)
        #expect(rule.hitCount == 7)
        #expect(rule.scope.languages == ["zh"])
        #expect(rule.scope.scenes == ["legal"])
    }

    @Test func enabledToggle_isMutable() {
        var rule = DictionaryRule(pattern: "a", replacement: "b")
        #expect(rule.enabled)
        rule.enabled = false
        #expect(rule.enabled == false)
    }

    @Test func scopeAny_matchesEverything() {
        #expect(DictionaryScope.any.matches(DictionaryContext()))
        #expect(DictionaryScope.any.matches(DictionaryContext(language: "en", scene: "x", appBundleID: "y")))
    }

    @Test func restrictedScope_requiresMatchingContext() {
        let scope = DictionaryScope(languages: ["zh"], scenes: ["legal"])
        #expect(scope.matches(DictionaryContext(language: "zh", scene: "legal")))
        #expect(scope.matches(DictionaryContext(language: "en", scene: "legal")) == false)
        // restricted axis with no context value → does not apply
        #expect(scope.matches(DictionaryContext(language: nil, scene: "legal")) == false)
    }

    @Test func scenePreset_decodes() throws {
        let json = #"{"id":"legal","name":"法律","hotwords":["北大法宝","PIPL"]}"#.data(using: .utf8)!
        let preset = try JSONDecoder().decode(ScenePreset.self, from: json)
        #expect(preset.id == "legal")
        #expect(preset.hotwords == ["北大法宝", "PIPL"])
        #expect(preset.enabled)
        #expect(preset.rules.isEmpty)
    }
}
