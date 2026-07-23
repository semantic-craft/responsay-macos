import XCTest
@testable import ResponsayMac

/// 315 — the sandbox demo copy follows the chosen 主要用途; the real-dictation
/// mechanism (312) is out of these tests' scope on purpose (copy only).
final class SandboxDemoScriptTests: XCTestCase {
    func testThreeUsages_threeDistinctSentences() {
        let demos = Usage.allCases.map { SandboxDemoScript.demo(for: $0) }
        XCTAssertEqual(Set(demos.map(\.suggestion)).count, Usage.allCases.count)
    }

    func testLegalDemo_isLawShaped() {
        let demo = SandboxDemoScript.demo(for: .legal)
        XCTAssertTrue(demo.suggestion.contains("违约"))
        XCTAssertEqual(demo.spoken, demo.suggestion)   // fallback hears the suggested line
        XCTAssertTrue(demo.inserted.hasPrefix(demo.spoken))   // insert = spoken + 句号
    }

    func testEnglishDemo_dictatesEnglish() {
        let demo = SandboxDemoScript.demo(for: .english)
        XCTAssertNotNil(demo.suggestion.range(of: "^[A-Za-z][A-Za-z ']*$", options: .regularExpression))
    }

    func testGeneralDemo_keepsThePre315Sentence() {
        // Continuity: the general fallback stays the sentence the scripted
        // simulation always used, so nothing regresses for the default path.
        let demo = SandboxDemoScript.demo(for: .general)
        XCTAssertEqual(demo.spoken, "今天天气真不错")
        XCTAssertEqual(demo.inserted, "今天天气真不错。")
    }
}
