import Testing
import Foundation
@testable import ResponsayCore

struct ExpressionResultTests {
    @Test func decodes_newFields_thinkingShiftAndAlternatives() throws {
        let json = """
        {"idiomatic":"Could you give me some pointers?","original":"please give me some advices",
         "reasons":["a"],"thinkingShift":"中式…/美式…","alternatives":["Any tips?"]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
        #expect(r.thinkingShift.contains("美式"))
        #expect(r.alternatives == ["Any tips?"])
    }

    @Test func decodes_legacyJSON_withoutNewFields_usesDefaults() throws {
        let json = #"{"idiomatic":"Let me check.","original":"我看看","reasons":["更口语"]}"#
            .data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
        #expect(r.thinkingShift.isEmpty)
        #expect(r.alternatives.isEmpty)
        #expect(r.intentNote.isEmpty)   // 422 — absent intentNote decodes to ""
    }

    // 422 — 猜测意图 carries an intentNote (原 X → 我理解为 Y); faithful / legacy leaves it "".
    @Test func decodes_intentNote_whenPresent() throws {
        let json = #"{"idiomatic":"x","original":"y","reasons":[],"intentNote":"原话「medium」→ 我理解为 native"}"#
            .data(using: .utf8)!
        let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
        #expect(r.intentNote.contains("我理解为"))
    }
}
