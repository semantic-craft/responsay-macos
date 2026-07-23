import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 517 — per-capture transient screen-term stash + the augmented ASR weak prompt.
/// The stash is memory-only (weak-prompt lane; never dictionary / vocabulary / hard-match / disk);
/// `beginHarvest` must return without waiting on AX (capture-start hot path).
final class TransientScreenTermsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.transientScreenTerms"

    override func setUp() {
        super.setUp()
        TransientScreenTerms.clear()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        TransientScreenTerms.clear()
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testBeginHarvestReturnsBeforeCollectAndLandsAsynchronously() async {
        let task = TransientScreenTerms.beginHarvest(
            isEnabled: true,
            dictionaryTerms: { ["arXiv"] },
            collect: {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return "Skills by Matt Pocock\nupgrade to Qwen3-ASR"
            })
        // 热路径断言:beginHarvest 已返回而 collect 还在睡 → 什么都没落。
        XCTAssertEqual(TransientScreenTerms.current, [])
        await task?.value
        XCTAssertEqual(TransientScreenTerms.current, ["Matt Pocock", "Qwen3-ASR"])
    }

    func testDisabledScreenContextClearsStaleAndNeverCollects() {
        TransientScreenTerms.set(["Stale"])
        let task = TransientScreenTerms.beginHarvest(
            isEnabled: false,
            dictionaryTerms: { [] },
            collect: { "Matt Pocock" })
        XCTAssertNil(task)   // guard 在 spawn 之前生效 → 无 AX、无任务
        XCTAssertEqual(TransientScreenTerms.current, [])
    }

    func testHarvestExcludesDictionaryTerms() async {
        let task = TransientScreenTerms.beginHarvest(
            isEnabled: true,
            dictionaryTerms: { ["Matt Pocock"] },
            collect: { "Skills by Matt Pocock and DeepSeek" })
        await task?.value
        XCTAssertEqual(TransientScreenTerms.current, ["DeepSeek"])
    }

    func testAsrWeakPromptAppendsStashAfterDictionaryAndWritesNothing() {
        XCTAssertTrue(ContextHotwordSettings.addManual("庭审笔录", defaults: defaults))
        TransientScreenTerms.set(["Matt Pocock"])

        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        let prompt = ContextHotwordSettings.asrWeakPrompt(defaults: defaults)
        let after = defaults.persistentDomain(forName: suite) as NSDictionary?

        XCTAssertEqual(prompt, ["庭审笔录", "Matt Pocock"])   // 词典在前、临时词在后
        XCTAssertEqual(before, after)                          // 零写入:词典/UserDefaults 纹丝不动
    }

    func testAsrWeakPromptIsByteIdenticalWhenStashEmpty() {
        XCTAssertTrue(ContextHotwordSettings.addManual("庭审笔录", defaults: defaults))
        XCTAssertEqual(
            ContextHotwordSettings.asrWeakPrompt(defaults: defaults),
            ContextHotwordSettings.biasingSets(defaults: defaults).weakPrompt)
    }
}
