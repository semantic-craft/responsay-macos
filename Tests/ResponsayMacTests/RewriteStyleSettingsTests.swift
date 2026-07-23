import ResponsayCore
import XCTest
@testable import ResponsayMac

/// 325 slice 4: the 重改写风格 picker stores either a built-in tone rawValue or a
/// `pack:<id>` reference. `activeStyle(lane:).heavyRewriteStyle` resolves it to a `RewriteStyle`
/// that `CaptureController` hands the VM. A pack that's gone (uninstalled import) falls back to
/// the natural tone rather than failing. These exercise the heavy-style resolution on the
/// dictation lane (no active pack set → the stored-tone fallback path).
@MainActor
final class RewriteStyleSettingsTests: XCTestCase {
    private let key = RewriteStyleSettings.key
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    private func pack(_ id: String) -> StylePack {
        StylePack(id: id, name: "风格 \(id)", systemPrompt: "改成某风格。", origin: .builtIn)
    }

    func testStoredToneResolvesToTone() {
        UserDefaults.standard.set("formal", forKey: key)
        XCTAssertEqual(RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: [pack("style.x")]).heavyRewriteStyle, .tone(.formal))
    }

    func testStoredPackIdResolvesToPack() {
        let p = pack("style.formal_expression.cn")
        UserDefaults.standard.set("pack:\(p.id)", forKey: key)
        XCTAssertEqual(RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: [p]).heavyRewriteStyle, .pack(p))
    }

    func testMissingPackFallsBackToNatural() {
        // Stored pack gone AND no 表达升级 backing available → the natural-tone default.
        UserDefaults.standard.set("pack:gone.cn", forKey: key)
        XCTAssertEqual(RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: []).heavyRewriteStyle, .tone(.natural))
    }

    func testUnsetWithNoPacksFallsBackToNaturalTone() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: []).heavyRewriteStyle, .tone(.natural))
    }

    /// (b, 2026-06-16) — with nothing activated/stored, the 表达升级 档's built-in default is its
    /// dedicated 表达升级 skill (not a bland tone), so the heavy tier reads heavy out of the box.
    func testUnsetDefaultsToExpressionUpgradeWhenAvailable() {
        UserDefaults.standard.removeObject(forKey: key)
        let upgrade = pack(SkillCategorizer.expressionUpgradeSkillID)
        XCTAssertEqual(RewriteStyleSettings.activeStyle(lane: .dictation, availablePacks: [upgrade]).heavyRewriteStyle, .pack(upgrade))
    }

    func testBundledPacksAreAvailable() throws {
        // The 3 bundled style.* packs are offered to the picker out of the box.
        let ids = RewriteStyleSettings.availablePacks().map(\.id)
        XCTAssertTrue(ids.contains("style.formal_expression.cn"))
    }
}
