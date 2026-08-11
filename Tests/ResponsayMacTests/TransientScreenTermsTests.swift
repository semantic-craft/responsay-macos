import XCTest
import ResponsayCore
import os
@testable import ResponsayMac

/// 517 — per-capture transient screen-term stash + the augmented ASR weak prompt.
/// The stash is memory-only (weak-prompt lane; never dictionary / vocabulary / hard-match / disk);
/// `beginHarvest` must return without waiting on AX (capture-start hot path).
final class TransientScreenTermsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var terms: TransientScreenTerms!
    private let suite = "test.transientScreenTerms"

    override func setUp() {
        super.setUp()
        terms = TransientScreenTerms()
        terms.prepareCapture()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        terms.finishCapture()
        terms = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testBeginHarvestReturnsBeforeCollectAndLandsAsynchronously() async {
        let task = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 101,
            dictionaryTerms: { ["arXiv"] },
            collect: { processIdentifier in
                XCTAssertEqual(processIdentifier, 101)
                try? await Task.sleep(nanoseconds: 200_000_000)
                return "Skills by Matt Pocock\nupgrade to Qwen3-ASR"
            })
        // 热路径断言:beginHarvest 已返回而 collect 还在睡 → 什么都没落。
        XCTAssertEqual(terms.current, [])
        await task?.value
        XCTAssertEqual(terms.current, ["Matt Pocock", "Qwen3-ASR"])
    }

    func testDisabledScreenContextClearsStaleAndNeverCollects() {
        terms.set(["Stale"])
        terms.prepareCapture()
        let task = terms.beginHarvest(
            isEnabled: false,
            targetProcessIdentifier: 102,
            dictionaryTerms: { [] },
            collect: { _ in "Matt Pocock" })
        XCTAssertNil(task)   // guard 在 spawn 之前生效 → 无 AX、无任务
        XCTAssertEqual(terms.current, [])
    }

    func testHarvestExcludesDictionaryTerms() async {
        let task = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 103,
            dictionaryTerms: { ["Matt Pocock"] },
            collect: { _ in "Skills by Matt Pocock and DeepSeek" })
        await task?.value
        XCTAssertEqual(terms.current, ["DeepSeek"])
    }

    func testOlderDetachedHarvestCannotOverwriteANewerCapture() async {
        let older = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 104,
            dictionaryTerms: { [] },
            collect: { _ in
                try? await Task.sleep(nanoseconds: 200_000_000)
                return "Old Capture"
            })
        terms.prepareCapture()
        let newer = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 105,
            dictionaryTerms: { [] },
            collect: { _ in "New Capture" })

        await newer?.value
        await older?.value

        XCTAssertEqual(terms.current, ["New Capture"])
    }

    func testOlderHarvestWaiterCannotReadANewerCapturesTerms() async {
        let collector = SuspendedScreenTextCollector()
        let olderGeneration = terms.prepareCapture()
        let olderHarvest = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 107,
            dictionaryTerms: { [] },
            collect: { _ in await collector.collect() })
        await collector.waitUntilStarted()

        let terms = self.terms!
        let olderWaiter = Task {
            await terms.awaitCurrentHarvest(
                for: olderGeneration,
                timeoutNanoseconds: 1_000_000_000)
        }

        terms.prepareCapture()
        let newerHarvest = terms.beginHarvest(
            isEnabled: true,
            targetProcessIdentifier: 108,
            dictionaryTerms: { [] },
            collect: { _ in "New Capture" })
        await newerHarvest?.value
        collector.resume(returning: "Old Capture")
        await olderHarvest?.value

        let olderTerms = await olderWaiter.value
        XCTAssertEqual(olderTerms, [])
        XCTAssertEqual(terms.current, ["New Capture"])
    }

    func testAwaitWithoutBeginHarvestReturnsWithinTheWholeBudget() async {
        terms.prepareCapture()
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await terms.awaitCurrentHarvest(timeoutNanoseconds: 10_000_000)

        XCTAssertEqual(result, [])
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(1))
    }

    func testPrivacyDenialsNeverInvokeVisibleTextCollector() {
        for decision: CaptureGateDecision in [
            .denied(.secureTextField),
            .denied(.sensitiveApp(bundleID: "com.1password.1password")),
            .denied(.sensitiveURL(prefix: "https://accounts.google.com"))
        ] {
            terms.prepareCapture()
            let didCollect = OSAllocatedUnfairLock(initialState: false)

            let task = terms.beginHarvest(
                isEnabled: true,
                gateDecision: decision,
                targetProcessIdentifier: 106,
                dictionaryTerms: { [] },
                collect: { _ in
                    didCollect.withLock { $0 = true }
                    return "must not be read"
                })

            XCTAssertNil(task)
            XCTAssertFalse(didCollect.withLock { $0 })
            XCTAssertEqual(terms.current, [])
        }
    }

    func testAsrWeakPromptAppendsStashAfterDictionaryAndWritesNothing() {
        XCTAssertTrue(ContextHotwordSettings.addManual("庭审笔录", defaults: defaults))
        terms.set(["Matt Pocock"])

        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        let prompt = ContextHotwordSettings.asrWeakPrompt(
            defaults: defaults,
            transientTerms: terms.current)
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

private actor SuspendedScreenTextCollector {
    private var continuation: CheckedContinuation<String?, Never>?

    func collect() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    nonisolated func resume(returning text: String?) {
        Task { await resolve(returning: text) }
    }

    private func resolve(returning text: String?) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}
