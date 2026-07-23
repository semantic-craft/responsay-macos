import XCTest
import ResponsayCore
@testable import ResponsayMac

final class ExpressInsertSettingsTests: XCTestCase {

    // MARK: - 3-state setting + migration from the old boolean

    func testFreshDefaultIsWriteAndExplain() {
        XCTAssertEqual(ExpressInsertSettings.mode(defaults: fresh("fresh")), .writeAndExplain)
    }

    func testMigratesLegacyAutoInsertTrueToWriteAndExplain() {
        let d = fresh("legacy-true")
        d.set(true, forKey: "expressAutoInsert")
        XCTAssertEqual(ExpressInsertSettings.mode(defaults: d), .writeAndExplain)
    }

    func testMigratesLegacyAutoInsertFalseToExplainOnly() {
        let d = fresh("legacy-false")
        d.set(false, forKey: "expressAutoInsert")
        XCTAssertEqual(ExpressInsertSettings.mode(defaults: d), .explainOnly)
    }

    func testStoredModeWinsOverLegacy() {
        let d = fresh("stored")
        d.set(true, forKey: "expressAutoInsert")          // legacy would say writeAndExplain
        ExpressInsertSettings.setMode(.explainOnly, defaults: d)
        XCTAssertEqual(ExpressInsertSettings.mode(defaults: d), .explainOnly)
    }

    // A legacy/unknown stored value (e.g. the retired `.directWrite`) falls back to the default —
    // 直接写入 was merged into 听写翻译 (Fn+Shift), so the mode no longer exists.
    func testRetiredDirectWriteFallsBackToDefault() {
        let d = fresh("retired")
        d.set("directWrite", forKey: ExpressInsertSettings.key)
        XCTAssertEqual(ExpressInsertSettings.mode(defaults: d), .writeAndExplain)
    }

    // MARK: - Routing: each output mode maps to the right capture OutputMode

    func testWriteAndExplainRoutesToTeachingFeedback() {
        XCTAssertEqual(ExpressOutputMode.writeAndExplain.outputMode, .teachingFeedback)
    }

    func testExplainOnlyRoutesToCoachRewrite() {
        XCTAssertEqual(ExpressOutputMode.explainOnly.outputMode, .coachRewrite)
    }

    private func fresh(_ suffix: String) -> UserDefaults {
        let name = "ExpressInsertSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
