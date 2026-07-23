import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 猎虫⑦ H12: after first-run completion, 菜单栏「重看新手引导…」reopens the FULL
/// wizard; its commit() used to re-apply wizard defaults wholesale — an innocent
/// click-through silently reset the user's configured ASR/TTS/Coach engines and
/// wiped custom shortcut bindings (313 shielded only the repair pane). Re-runs
/// now prefill from the live stores and commit only what actually changed.
@MainActor
final class OnboardingRerunCommitTests: XCTestCase {
    private let keys = [
        OnboardingWindowController.completedKey, "onboardingStep", "shortcutScheme",
        ASREngine.defaultsKey, TTSEngine.defaultsKey,
        "legalSkillsEnabled", EnabledLegalSkillStore.defaultsKey, AutoLearnHotwordSettings.key,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        for key in keys { saved[key] = d.object(forKey: key) }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for key in keys {
            if let value = saved[key] { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    func testRerunClickThroughLeavesLiveConfigUntouched() {
        let d = UserDefaults.standard
        // A configured user: completed onboarding, cloud ASR + cloud TTS,
        // non-default shortcut scheme. A cloud ASR engine prefills the 云端 engine choice.
        d.set(true, forKey: OnboardingWindowController.completedKey)
        d.set(ASREngine.cloudMimo.rawValue, forKey: ASREngine.defaultsKey)
        d.set(TTSEngine.cloudQwen.rawValue, forKey: TTSEngine.defaultsKey)
        d.set("other", forKey: "shortcutScheme")
        d.set(false, forKey: "legalSkillsEnabled")

        let model = OnboardingModel()
        // Prefill mirrors the live config…
        XCTAssertEqual(model.engine, .cloud)
        XCTAssertEqual(model.shortcutScheme, .other)
        XCTAssertEqual(model.usage, .legal)

        model.commit()   // …so an unchanged walk-through writes nothing back

        XCTAssertEqual(d.string(forKey: ASREngine.defaultsKey), ASREngine.cloudMimo.rawValue)
        XCTAssertEqual(d.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudQwen.rawValue)
        XCTAssertEqual(d.string(forKey: "shortcutScheme"), "other")
        XCTAssertEqual(d.object(forKey: "legalSkillsEnabled") as? Bool, false)
    }

    func testRerunWithRealChangeStillApplies() {
        let d = UserDefaults.standard
        d.set(true, forKey: OnboardingWindowController.completedKey)
        d.set(ASREngine.cloudMimo.rawValue, forKey: ASREngine.defaultsKey)

        let model = OnboardingModel()
        model.engine = .local   // deliberate change on a re-run
        model.commit()

        // Switching to the local engine moves ASR off the cloud baseline.
        XCTAssertNotEqual(d.string(forKey: ASREngine.defaultsKey), ASREngine.cloudMimo.rawValue)
    }

    func testFirstRunStillCommitsDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)
        d.removeObject(forKey: ASREngine.defaultsKey)

        let model = OnboardingModel()
        model.commit()

        // First run keeps the original behavior: the local-engine ASR default lands.
        XCTAssertNotNil(d.string(forKey: ASREngine.defaultsKey))
    }

    func testFirstRunGeneralUsageDoesNotWriteGlobalLegalGate() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)
        d.removeObject(forKey: "legalSkillsEnabled")

        let model = OnboardingModel()
        model.usage = .general
        model.commit()

        XCTAssertNil(d.object(forKey: "legalSkillsEnabled"))
    }

    func testFirstRunEnglishUsageDoesNotWriteGlobalLegalGate() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)
        d.removeObject(forKey: "legalSkillsEnabled")

        let model = OnboardingModel()
        model.usage = .english
        model.commit()

        XCTAssertNil(d.object(forKey: "legalSkillsEnabled"))
    }

    func testLegalOnboardingFlowShowsDemoBeforeSandbox() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)

        let model = OnboardingModel()
        model.usage = .legal

        XCTAssertEqual(model.steps, [
            .skin, .engine, .snapOCR, .permissions, .hotkey,
            .autoLearn, .demo, .sandbox, .basicsLayer, .done,
        ])
    }

    func testNonLegalOnboardingFlowStillShowsDemoBeforeSandbox() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)

        let model = OnboardingModel()
        model.usage = .general

        XCTAssertEqual(model.steps, [
            .skin, .engine, .snapOCR, .permissions, .hotkey,
            .autoLearn, .demo, .sandbox, .basicsLayer, .done,
        ])
    }

    func testDemoStepDoesNotShiftPersistedStepRawValues() {
        XCTAssertEqual(OnboardingStep.sandbox.rawValue, 7)
        XCTAssertEqual(OnboardingStep.basicsLayer.rawValue, 8)
        XCTAssertEqual(OnboardingStep.done.rawValue, 9)
        XCTAssertEqual(OnboardingStep.demo.rawValue, 10)
        XCTAssertEqual(OnboardingStep.autoLearn.rawValue, 11)   // new step takes a fresh raw value
        XCTAssertEqual(OnboardingStep(rawValue: 7), .sandbox)
        // autoLearn inserted after hotkey shifts DISPLAY positions (.number), never raw values.
        XCTAssertEqual(OnboardingStep.autoLearn.number, 6)
        XCTAssertEqual(OnboardingStep.demo.number, 7)
        XCTAssertEqual(OnboardingStep.sandbox.number, 8)
    }

    // MARK: - 自动学习 onboarding opt-in (audit 2026-06-20)

    func testFirstRunCommitsAutoLearnOptIn() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)
        d.removeObject(forKey: AutoLearnHotwordSettings.key)

        let model = OnboardingModel()
        XCTAssertTrue(model.autoLearnEnabled)   // first run pre-selects 开启（推荐）
        model.commit()
        XCTAssertEqual(d.object(forKey: AutoLearnHotwordSettings.key) as? Bool, true)
    }

    func testFirstRunCanDeclineAutoLearn() {
        let d = UserDefaults.standard
        d.removeObject(forKey: OnboardingWindowController.completedKey)
        d.removeObject(forKey: AutoLearnHotwordSettings.key)

        let model = OnboardingModel()
        model.autoLearnEnabled = false   // user picks 先不开
        model.commit()
        XCTAssertEqual(d.object(forKey: AutoLearnHotwordSettings.key) as? Bool, false)
    }

    func testRerunDoesNotResurrectDeclinedAutoLearn() {
        let d = UserDefaults.standard
        d.set(true, forKey: OnboardingWindowController.completedKey)
        d.set(false, forKey: AutoLearnHotwordSettings.key)   // user previously declined

        let model = OnboardingModel()
        XCTAssertFalse(model.autoLearnEnabled)   // prefilled OFF from the live setting, not the ON default
        model.commit()                            // innocent re-watch must not flip it back on
        XCTAssertEqual(d.object(forKey: AutoLearnHotwordSettings.key) as? Bool, false)
    }

    func testRerunCanFlipAutoLearnOff() {
        let d = UserDefaults.standard
        d.set(true, forKey: OnboardingWindowController.completedKey)
        d.set(true, forKey: AutoLearnHotwordSettings.key)

        let model = OnboardingModel()
        model.autoLearnEnabled = false   // deliberate change on a re-run
        model.commit()
        XCTAssertEqual(d.object(forKey: AutoLearnHotwordSettings.key) as? Bool, false)
    }
}
