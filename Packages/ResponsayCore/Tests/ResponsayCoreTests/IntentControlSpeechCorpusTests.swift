import Foundation
import Testing
@testable import ResponsayCore

// #561 — the paired control-speech corpus (Testing Decisions 4–6): Chinese / English / 中英混说
// cases for safe auto-insert, mandatory review, and no-control negatives. Each auto-insert case
// asserts all four externally-visible facts — the final text (deterministic source render), the
// EXCLUDED source IDs, the terminal outcome, and (for review cases) the review reason. Plans are
// fixture-built: the corpus scores the safety spine, not any provider.

typealias CorpusPlan = @Sendable ([IntentSourceUnit]) -> IntentPlan

/// Roles by unit index + supersessions by (winner, loser, cue) indexes.
private func plan(
    _ decision: IntentPlanDecision,
    roles: [IntentSourceRole],
    supersessions: [(winner: Int, loser: Int, cue: Int)] = []
) -> CorpusPlan {
    { sources in
        IntentPlan(
            version: 1,
            decision: decision,
            units: zip(sources, roles).map { .init(source: .init($0), role: $1) },
            supersessions: supersessions.map {
                .init(
                    winner: .init(sources[$0.winner]),
                    loser: .init(sources[$0.loser]),
                    cue: .init(sources[$0.cue]))
            })
    }
}

private func allContent(_ decision: IntentPlanDecision) -> CorpusPlan {
    { sources in
        IntentPlan(
            version: 1,
            decision: decision,
            units: sources.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
}

/// Pipeline-level terminal outcome for a fixture plan.
private func compile(
    _ transcript: String,
    locale: CaptureLocale,
    plan: @escaping CorpusPlan
) async -> IntentCompilationOutcome {
    let compiler = FixtureIntentCompiler { input in
        try JSONEncoder().encode(plan(input.sourceUnits))
    }
    return await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: transcript,
        locale: locale,
        allowedContext: nil,
        routePolicy: .injectedCompiler)
}

/// Verifier/renderer-level facts: deterministic final text + excluded source IDs.
private func render(
    _ transcript: String,
    plan: CorpusPlan
) throws -> (text: String, excludedIDs: Set<String>) {
    let units = IntentSourceSegmenter.segment(transcript)
    let verified = try IntentPlanVerifier.verify(plan(units), sourceUnits: units, transcript: transcript)
    let draft = IntentSourceRenderer.render(verified)
    return (
        TextCorrectionRules.apply(to: draft.text),
        Set(units.map(\.id)).subtracting(draft.sourceIDs))
}

// MARK: - 安全自动插入 · corrections

struct IntentCorrectionCorpus {
    struct Case {
        let name: String
        let transcript: String
        let locale: CaptureLocale
        let plan: CorpusPlan
        let text: String
        let excluded: Set<String>
    }

    static let autoInsert: [Case] = [
        Case(
            name: "zh 近距改口",
            transcript: "周三开会，不对，周四开会",
            locale: .chinese,
            plan: plan(.render, roles: [.content, .correction, .content],
                       supersessions: [(winner: 2, loser: 0, cue: 1)]),
            text: "周四开会",
            excluded: ["source-0000", "source-0001"]),
        Case(
            name: "zh 跨多个 source units 的晚到改口",
            transcript: "先订会议室，然后通知大家周三开会，材料我来准备，说错了，是周四开会",
            locale: .chinese,
            plan: plan(.render, roles: [.content, .content, .content, .correction, .content],
                       supersessions: [(winner: 4, loser: 1, cue: 3)]),
            text: "先订会议室，材料我来准备，是周四开会",
            excluded: ["source-0001", "source-0003"]),
        Case(
            name: "zh 句尾回指第一句（referent 优先于就近）",
            transcript: "会议定在周三下午，材料让小李准备，不对，是周四下午",
            locale: .chinese,
            plan: plan(.render, roles: [.content, .content, .correction, .content],
                       supersessions: [(winner: 3, loser: 0, cue: 2)]),
            text: "材料让小李准备，是周四下午",
            excluded: ["source-0000", "source-0002"]),
        Case(
            name: "zh 同一目标连续两次修正——只留最终决定",
            transcript: "发货定在周三，不对，周四，呃不对，周五发货",
            locale: .chinese,
            plan: plan(
                .render,
                roles: [.content, .correction, .content, .correction, .content],
                supersessions: [(winner: 2, loser: 0, cue: 1), (winner: 4, loser: 2, cue: 3)]),
            text: "周五发货",
            excluded: ["source-0000", "source-0001", "source-0002", "source-0003"]),
        Case(
            name: "en near correction (rendered units keep their leading space)",
            transcript: "Send the draft on Friday, no wait, send it on Monday",
            locale: .english,
            plan: plan(.render, roles: [.content, .correction, .content],
                       supersessions: [(winner: 2, loser: 0, cue: 1)]),
            text: " send it on Monday",
            excluded: ["source-0000", "source-0001"]),
        Case(
            name: "中英混说改口",
            transcript: "把 deadline 定在 Friday，不对，改到下周一",
            locale: .chinese,
            plan: plan(.render, roles: [.content, .correction, .content],
                       supersessions: [(winner: 2, loser: 0, cue: 1)]),
            text: "改到下周一",
            excluded: ["source-0000", "source-0001"])
    ]

    @Test(arguments: autoInsert.map(\.name))
    func autoInsertCase(_ name: String) async throws {
        let corpusCase = Self.autoInsert.first { $0.name == name }!

        let rendered = try render(corpusCase.transcript, plan: corpusCase.plan)
        #expect(rendered.text == corpusCase.text, "\(name): final text")
        #expect(rendered.excludedIDs == corpusCase.excluded, "\(name): excluded IDs")

        let outcome = await compile(corpusCase.transcript, locale: corpusCase.locale, plan: corpusCase.plan)
        #expect(outcome == .insertable(text: corpusCase.text, route: .intentPlan), "\(name): outcome")
    }
}

// MARK: - 安全自动插入 · side notes（配对：去掉旁注后与无旁注版本逐字相同）

struct IntentSideNoteCorpus {
    struct Pair {
        let name: String
        let base: String        // 无旁注版本（noIntentControl 自动走普通整理）
        let noted: String       // 带旁注版本
        let roles: [IntentSourceRole]
        let noteTokens: [String]
        let excluded: Set<String>
    }

    static let pairs: [Pair] = [
        Pair(
            name: "zh 中段旁注",
            base: "帮我谢谢小王，他昨天帮了大忙",
            noted: "帮我谢谢小王，这句不用写，他昨天帮了大忙",
            roles: [.content, .sideNote, .content],
            noteTokens: ["这句不用写"],
            excluded: ["source-0001"]),
        Pair(
            name: "en mid-utterance note-to-self",
            base: "Thanks for the docs, see you Monday",
            noted: "Thanks for the docs, note to self I still owe them feedback, see you Monday",
            roles: [.content, .sideNote, .content],
            noteTokens: ["note to self", "owe them feedback"],
            excluded: ["source-0001"]),
        Pair(
            name: "混说旁注",
            base: "跟 Kevin 说 demo 材料我下班前发过去，今天就要",
            noted: "跟 Kevin 说 demo 材料我下班前发过去，这句不用写，今天就要",
            roles: [.content, .sideNote, .content],
            noteTokens: ["这句不用写"],
            excluded: ["source-0001"])
    ]

    @Test(arguments: pairs.map(\.name))
    func pairedZeroLeak(_ name: String) async throws {
        let pair = Self.pairs.first { $0.name == name }!
        let notedPlan = plan(.render, roles: pair.roles)

        // 带旁注版本的确定性成稿 == 无旁注版本的原文——旁注零渲染字符（Testing Decision 5）。
        let rendered = try render(pair.noted, plan: notedPlan)
        #expect(rendered.text == pair.base, "\(name): noted render equals no-note version")
        #expect(rendered.excludedIDs == pair.excluded, "\(name): excluded IDs")
        for token in pair.noteTokens {
            #expect(!rendered.text.contains(token), "\(name): zero note leakage")
        }

        let notedOutcome = await compile(pair.noted, locale: .chinese, plan: notedPlan)
        #expect(notedOutcome == .insertable(text: pair.base, route: .intentPlan), "\(name): noted outcome")

        // 无旁注版本自动走显式普通整理路由。
        let baseOutcome = await compile(pair.base, locale: .chinese, plan: allContent(.noIntentControl))
        #expect(baseOutcome == .insertable(text: pair.base, route: .ordinaryPolished), "\(name): base outcome")
    }
}

// MARK: - 必须 review

@Test func corpusReview_twoPlausibleTargets_compilerAbstains() async {
    // 两处「周三」都是合理 referent → 编译器弃权，不靠"最后出现者优先"猜测。
    let outcome = await compile("周三交初稿，周三开评审会，不对，是周四", locale: .chinese,
                                plan: allContent(.needsReview))
    #expect(outcome == .needsReview(reason: .compilerRequested))
}

@Test func corpusReview_sideNoteBoundaryUnclear_compilerAbstains() async {
    // 「顺便说一句…」既可能是旁注也可能是要写的话 → review，不猜测（User Story 22）。
    let outcome = await compile("帮我发个周报，顺便说一句今天路上堵疯了", locale: .chinese,
                                plan: allContent(.needsReview))
    #expect(outcome == .needsReview(reason: .compilerRequested))
}

@Test func corpusReview_unexplainedCues_preflightVeto_zhEnMixed() async {
    // plan 漏掉明显 cue → veto。英文改口、混说旁注各一例（中文例在 IntentCueCoverageTests）。
    let english = await compile("Meeting Wednesday, no wait, Thursday", locale: .english,
                                plan: allContent(.noIntentControl))
    #expect(english == .needsReview(reason: .unexplainedCorrectionCue))

    let mixed = await compile("跟 Kevin 说 OK，这句不用写，他知道背景", locale: .chinese,
                              plan: allContent(.render))
    #expect(mixed == .needsReview(reason: .unexplainedSideNoteCue))
}

@Test func corpusTerminal_sideNoteInsideSupersession_isRejectedNotInserted() async {
    // 结构非法（旁注被当作 supersession 一方）→ safe-unavailable，绝不自动插入。
    let outcome = await compile(
        "别写这句，不对，把这句写上", locale: .chinese,
        plan: plan(.render, roles: [.sideNote, .correction, .content],
                   supersessions: [(winner: 2, loser: 0, cue: 1)]))
    #expect(outcome == .safeUnavailable(reason: .invalidPlan))
}

// MARK: - 无控制语负例

@Test func corpusNegative_ordinaryProse_staysOrdinary_zhEnMixedQuoted() async {
    let negatives = [
        "不对称加密在这个场景里更合适，麻烦你评估一下",
        "The quarterly report is ready for review, thanks for waiting",
        "请把 slides 发给 Chen 教授，谢谢",
        "他说“不对，是周四”，我已经记下来了"
    ]
    for transcript in negatives {
        // 前置扫描零命中——普通 prose 不被误分类为旁注或改口。
        let hits = IntentCuePreflight.scan(
            transcript: transcript, units: IntentSourceSegmenter.segment(transcript))
        #expect(hits.isEmpty, "\(transcript): preflight must not fire")

        // 合法 noIntentControl → 显式普通整理路由，逐字保留。
        let outcome = await compile(transcript, locale: .chinese, plan: allContent(.noIntentControl))
        #expect(outcome == .insertable(text: transcript, route: .ordinaryPolished), "\(transcript)")
    }
}
