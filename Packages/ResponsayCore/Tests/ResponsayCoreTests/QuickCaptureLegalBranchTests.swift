import Testing
import Foundation
@testable import ResponsayCore

/// QuickCaptureViewModel legal skill execution — the shared 划词菜单 oneShot path
/// (`runLegalSkillOnSelection`): privacy gate → send-preview → execute → record, never
/// inserting. (The standalone `.legalSuggest` palette branch was retired with 划词技能互动;
/// the machinery it shared is now exercised through the direct skill-run entry.)
@MainActor
private func makeLegalVM(
    context: ExpressionContext,
    withRuntime: Bool = true,
    executor: LegalSkillExecutorAPI? = nil,
    gate: CaptureGateDecision = .allowed,
    profile: LegalPracticeProfile? = nil,
    recorder: (@MainActor (LegalSkillRun) -> Void)? = nil
) throws -> (QuickCaptureViewModel, MockTextInserter) {
    let inserter = MockTextInserter()
    let store = FileCaptureStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let runtime = withRuntime ? try LegalSkillRuntime.bundled(executor: executor) : nil
    let vm = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(),
        store: store,
        inserter: inserter,
        contextProvider: { context },
        legalRuntime: runtime,
        legalProfileProvider: { profile },
        legalGateProvider: { gate },
        legalRunRecorder: recorder)
    return (vm, inserter)
}

/// The bundled skill the 划词菜单 runs directly in these tests (litigation scene).
private let runSkillID = "verification.fact_check.cn"

/// A profile that opts into cloud (so non-sensitive selections skip the send-preview gate).
@MainActor private func cloudFirstProfile() -> LegalPracticeProfile {
    LegalPracticeProfile(id: "p", role: .practitioner, modelPreference: .cloudFirst,
                         createdAt: "t", updatedAt: "t")
}

/// A profile that keeps everything local.
@MainActor private func localFirstProfile() -> LegalPracticeProfile {
    LegalPracticeProfile(id: "p", role: .student, modelPreference: .localFirst,
                         createdAt: "t", updatedAt: "t")
}

/// 用户选择"每次询问"——发送前确认卡的合法触发来源(不再靠"敏感内容"自动触发)。
@MainActor private func askEachTimeProfile() -> LegalPracticeProfile {
    LegalPracticeProfile(id: "p", role: .practitioner, modelPreference: .askEachTime,
                         createdAt: "t", updatedAt: "t")
}

@MainActor private final class RunCollector { var runs: [LegalSkillRun] = [] }

@Test @MainActor func runLegalSkill_populatesCardWithoutInserting() async throws {
    let ctx = ExpressionContext(
        appName: "Microsoft Word",
        bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx",
        selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    // cloudFirst → skip the preview gate; no executor → execute errors, but the card was built
    // and nothing was inserted along the way.
    let (vm, inserter) = try makeLegalVM(context: ctx, profile: cloudFirstProfile())

    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款,构成违约。")

    #expect(vm.legalCandidates.map(\.skillId) == [runSkillID])
    #expect(inserter.inserted.isEmpty)            // legal skills NEVER insert
    #expect(vm.result == nil)                      // not a coach result
}

@Test @MainActor func runLegalSkill_withoutRuntime_failsClearly() async throws {
    let (vm, inserter) = try makeLegalVM(context: ExpressionContext(selectedText: "x"), withRuntime: false)
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "x")
    #expect(vm.phase == .error)
    #expect(vm.errorMessage?.isEmpty == false)
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func runLegalSkill_withoutExecutor_failsClearlyNoInsert() async throws {
    // Runtime present but no executor wired → execute throws notConfigured, surfaced as
    // an error, never an insertion. cloudFirst → execute directly (skip the preview gate).
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx, profile: cloudFirstProfile())

    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款,构成违约。")

    #expect(inserter.inserted.isEmpty)
    #expect(vm.phase == .error)
}

@Test @MainActor func runLegalSkill_capturesResponse_withoutInserting() async throws {
    // cloudFirst + non-sensitive text → no send-preview gate → runs directly, captures the
    // structured response for the output view (107), never inserts.
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "已生成证据论证矩阵")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx, executor: mock, profile: cloudFirstProfile())

    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款,构成违约。")

    #expect(vm.legalSendConfirm == nil)           // non-sensitive cloudFirst → no confirm gate
    #expect(vm.legalResponse?.summary == "已生成证据论证矩阵")
    #expect(inserter.inserted.isEmpty)            // legal output is rendered (107), never inserted
}

@Test @MainActor func askEachTime_showsSendPreviewBeforeAnyCloudCall() async throws {
    // 用户选「每次询问」→ 发送前确认卡,确认前不执行/不插入。触发来源是用户偏好,不是"敏感内容"。
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "已生成")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "代理词.docx", selectedText: "需主张违约责任。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, inserter) = try makeLegalVM(context: ctx, executor: mock, profile: askEachTimeProfile())

    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "需主张违约责任。")
    // gated: preview shown, nothing executed or inserted yet
    #expect(vm.legalSendConfirm?.requiresUserConfirm == true)
    #expect(vm.legalSendConfirm?.sendFields.contains(.selectedText) == true)
    #expect(vm.legalResponse == nil)
    #expect(await mock.calls.isEmpty)

    await vm.confirmLegalSend()
    #expect(vm.legalSendConfirm == nil)
    #expect(vm.legalResponse?.summary == "已生成")
    #expect(inserter.inserted.isEmpty)
}

@Test @MainActor func cancelLegalSend_sendsNothing() async throws {
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "代理词.docx", selectedText: "需主张违约责任。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock, profile: askEachTimeProfile())
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "需主张违约责任。")
    #expect(vm.legalSendConfirm != nil)

    vm.cancelLegalSend()
    #expect(vm.legalSendConfirm == nil)
    #expect(vm.legalResponse == nil)
    #expect(await mock.calls.isEmpty)             // nothing sent
}

@Test @MainActor func secureField_noLongerBlocks_runsNormally() async throws {
    // 2026-06-25 反转: 安全输入框不再阻断法律技能。cloudFirst → 直接执行并产出结果(不再报错/拦截)。
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "已生成")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        selectedText: "被告拖欠货款。", textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(
        context: ctx, executor: mock, gate: .denied(.secureTextField), profile: cloudFirstProfile())
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款。")

    #expect(vm.phase != .error)                   // 不再被阻断
    #expect(vm.legalResponse?.summary == "已生成")
    #expect(await !mock.calls.isEmpty)            // 实际执行了
}

@Test @MainActor func localFirstProfile_routesLocalOnly_noPreview() async throws {
    // 109 profile drives 110: localFirst → localOnly → runs directly (no cloud preview).
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON(summary: "本地结果")])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock, profile: localFirstProfile())
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款,构成违约。")

    #expect(vm.legalSendConfirm == nil)                      // local → no cloud preview
    #expect(vm.legalResponse?.summary == "本地结果")
    #expect(await mock.calls.first?.modelRoute == .localOnly) // privacy route forwarded
}

@Test @MainActor func execute_recordsRunAsHashNotRawText() async throws {
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let collector = RunCollector()
    let secret = "被告拖欠货款,构成违约。"
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: secret,
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(
        context: ctx, executor: mock, profile: cloudFirstProfile(),
        recorder: { collector.runs.append($0) })
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: secret)

    let run = try #require(collector.runs.first)
    #expect(run.skillId == runSkillID)
    #expect(run.scene == .litigation)
    #expect(run.modelRoute == .cloudAllowed)
    #expect(run.contextHash.hasPrefix("sha256:"))
    #expect(run.contextHash.contains(secret) == false)        // hash, never the raw text
}

@Test @MainActor func defaultAskEachTime_alwaysShowsSendPreview() async throws {
    // No profile → askEachTime default → every cloud legal call is gated by the preview (AC3).
    let mock = MockLegalExecutor(outputs: [legalGoodOutputJSON()])
    let ctx = ExpressionContext(
        appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word",
        windowTitle: "起诉状.docx", selectedText: "被告拖欠货款,构成违约。",
        textBeforeCursor: "一、事实与理由\n……")
    let (vm, _) = try makeLegalVM(context: ctx, executor: mock)   // no profile
    await vm.runLegalSkillOnSelection(skillId: runSkillID, text: "被告拖欠货款,构成违约。")

    #expect(vm.legalSendConfirm != nil)
    #expect(vm.legalSendConfirm?.sendFields == [.selectedText, .sceneTag, .appCategory])
}

@Test @MainActor func evaluateScene_usesBrowserURLWhenSelectionSignalsAreInsufficient() throws {
    // evaluateScene stays live for the 任意提问 legal/general router; browser-URL boosts the scene.
    let vagueText = "这段材料需要核验一下。"
    let noURL = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(result: nil, error: nil),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter(),
        contextProvider: { ExpressionContext(selectedText: nil) },
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))

    let degraded = try #require(noURL.evaluateScene(text: vagueText))
    #expect(degraded.scene == .unknown)

    // 508: the full URL now reaches the LLM payload (the old host-only privacy guard was
    // intentionally reversed — user opt-in via 屏幕上下文). The scene router below still
    // classifies host-only internally, so routing/reasons stay path-free.
    let cnkiURL = "https://kns.cnki.net/kcms/detail/secret-paper?query=private"
    let cnkiContext = ExpressionContext(selectedText: nil, browserURL: cnkiURL)
    #expect(cnkiContext.browserURL == cnkiURL)                       // full URL, not host
    #expect(cnkiContext.jsonObject["browserURL"] as? String == cnkiURL)  // reaches the LLM payload

    let withCNKI = QuickCaptureViewModel(
        speech: MockSpeechCaptureService(),
        coach: MockCoachAPI(result: nil, error: nil),
        store: FileCaptureStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        inserter: MockTextInserter(),
        contextProvider: { cnkiContext },
        legalRuntime: try LegalSkillRuntime.bundled(executor: nil))

    let boosted = try #require(withCNKI.evaluateScene(text: vagueText))
    #expect(boosted.scene == .academicWriting)
    #expect(boosted.reasons.contains { $0.contains("网址 academicDatabase") })
    #expect(boosted.reasons.contains { $0.contains("secret-paper") } == false)
    #expect(boosted.reasons.contains { $0.contains("private") } == false)
}

@Test @MainActor func legacyCoachPath_unaffectedByLegalAdditions() async throws {
    // Sanity: a normal coach capture still lands in review and inserts on confirm.
    let inserter = MockTextInserter()
    let speech = MockSpeechCaptureService(); speech.transcriptToReturn = "i want fix bug"
    let store = FileCaptureStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let vm = QuickCaptureViewModel(
        speech: speech,
        coach: MockCoachAPI(result: ExpressionResult(
            idiomatic: "I want to fix the bug.", original: "i want fix bug", reasons: ["缺 to"])),
        store: store, inserter: inserter)

    await vm.toggle(outputMode: .coachRewrite)   // start
    await vm.toggle(outputMode: .coachRewrite)   // stop + process

    #expect(vm.phase == .review)
    #expect(vm.legalCandidates.isEmpty)           // legal state stays empty on legacy paths
}
