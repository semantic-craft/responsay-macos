import XCTest
@testable import ResponsayMac

/// 415 — 技能库搬进设置 + 主窗砍 tab。These pin the navigation IA decisions
/// (an enum-level contract, view rendering verified by build + computer-use):
///   • the main window no longer offers a 法律技能 tab (主窗瘦身)
///   • settings exposes 技能库 + 技能偏好 entries, both in the 法律 domain group,
///     and no entry still titled「法律技能」
@MainActor
final class SkillsLibraryIATests: XCTestCase {

    func testMainWindowNavigationDropsLegalTab() {
        XCTAssertEqual(MainWindowView.Section.allCases, [.overview, .history],
                       "主窗导航 = 主面板 / 历史；识别词典与法律技能均已搬进设置")
        XCTAssertFalse(MainWindowView.Section.allCases.contains { $0.rawValue == "legal" },
                       "法律技能 tab 不应回到主窗")
    }

    func testSettingsExposesSkillsLibraryAndLegalConfigInLegalDomain() {
        let titles = SettingsSection.allCases.map(\.title)
        // 技能平台 = the migrated rich skills screen; 技能偏好 = output mode + user profile.
        XCTAssertEqual(SettingsSection.legalSkills.title, "技能平台")
        XCTAssertTrue(titles.contains("技能偏好"),
                      "结果输出方式 + 用户画像 需有一个设置入口承接")
        XCTAssertFalse(titles.contains("法律技能"),
                       "旧「法律技能」入口已改名为「技能平台」")
        // The skills-library, its legal config, and 法律 AI all live in the 法律 domain group.
        XCTAssertEqual(SettingsSection.legalSkills.domain, .legal)
        XCTAssertEqual(SettingsSection.legalConfig.domain, .legal)
        XCTAssertEqual(SettingsSection.verify.domain, .legal)
    }
}
