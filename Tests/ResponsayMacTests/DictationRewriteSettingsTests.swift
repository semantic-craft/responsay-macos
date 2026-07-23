import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 393 — 听写默认力度的单一真相源。默认（未设置过 key）= 轻度改写清稿（对标 Typeless）；
/// 用户开「如实输入」(= 关轻度改写) 才走 ASR 原文逐字。菜单栏开关与设置面板共用此 key。
final class DictationRewriteSettingsTests: XCTestCase {

    func testDictationDefaultsToCleanPolish() {
        // 全新 / 清空设置：默认轻度改写（清稿），路由到 polish。
        let defaults = freshDefaults("default")
        XCTAssertTrue(DictationRewriteSettings.lightRewriteEnabled(defaults))
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .polishedTranscript)
    }

    func testLightRewriteOnRoutesToPolish() {
        // 打开「轻度改写」→ 听写走轻度整理（加标点、去口癖）。
        let defaults = freshDefaults("on")
        defaults.set(true, forKey: DictationRewriteSettings.key)
        XCTAssertTrue(DictationRewriteSettings.lightRewriteEnabled(defaults))
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .polishedTranscript)
    }

    func testLightRewriteOffRoutesToRaw() {
        let defaults = freshDefaults("off")
        defaults.set(false, forKey: DictationRewriteSettings.key)
        XCTAssertFalse(DictationRewriteSettings.lightRewriteEnabled(defaults))
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .rawTranscript)
    }

    // MARK: - 558 意图成稿（实验）三档路由

    func testIntentAwareDefaultsOff() {
        // 未设置过 → 实验默认关，听写仍走轻度整理。
        let defaults = freshDefaults("intent-default")
        XCTAssertFalse(IntentDictationSettings.isEnabled(defaults))
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .polishedTranscript)
    }

    func testIntentAwareOnTopOfLightRewriteRoutesToIntent() {
        let defaults = freshDefaults("intent-on")
        defaults.set(true, forKey: DictationRewriteSettings.key)
        IntentDictationSettings.setEnabled(true, defaults)
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .intentAwareDictation)
    }

    func testVerbatimEscapeHatchBeatsIntentAware() {
        // 如实输入是逃生口：即使实验开着，关掉轻度改写仍必须逐字上屏。
        let defaults = freshDefaults("intent-verbatim")
        defaults.set(false, forKey: DictationRewriteSettings.key)
        IntentDictationSettings.setEnabled(true, defaults)
        XCTAssertEqual(DictationRewriteSettings.dictationOutputMode(defaults), .rawTranscript)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "DictationRewriteSettingsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
