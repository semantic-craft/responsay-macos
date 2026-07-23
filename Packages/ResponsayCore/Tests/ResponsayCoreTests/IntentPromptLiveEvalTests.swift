import Foundation
import Testing
@testable import ResponsayCore

/// #575 — opt-in LIVE prompt evaluation against real cloud providers. The whole point is to
/// tune the plan prompt until WEAK models hold the strict contract, offline, instead of
/// discovering failures one release at a time on a real Mac.
///
/// Gated on `RESPONSAY_INTENT_EVAL=1` plus per-provider keys (`MIMO_KEY`, `QWEN_KEY`) in the
/// environment — absent ⇒ SKIPPED (never faked). Keys never appear in the repo or the output;
/// the report prints outcome classes, failure categories and draft text of OUR OWN eval
/// sentences only. Battery = the real 2026-07-13 session transcripts (five blocked-card
/// shapes) + correction / side-note / prose-negative coverage.
private struct EvalCase {
    let id: String
    let transcript: String
    let expectInsertable: Bool
    let mustContain: [String]
    let mustNotContain: [String]
}

private let battery: [EvalCase] = [
    .init(id: "clue-golden",
          transcript: "给这个我的学生何振杰写一封邮件，何是如何的何，振是城镇的振，杰是杰出的杰。",
          expectInsertable: true, mustContain: ["何镇杰"], mustNotContain: ["城镇", "如何的"]),
    .init(id: "clue-all-homophone-name",
          transcript: "给我的学生和郑姐写一封邮件，和是如何的和，镇呢是城镇的镇，结是结束的结。",
          expectInsertable: true, mustContain: ["何镇结"], mustNotContain: ["和郑姐", "城镇"]),
    .init(id: "clue-announced-correct",
          transcript: "给我的学生何振杰写封邮件。何是如何的何，振是城镇的镇，杰是杰出的杰。",
          expectInsertable: true, mustContain: ["何镇杰"], mustNotContain: ["城镇"]),
    .init(id: "false-start",
          transcript: "我，帮我给我的学生何正杰写一封邮件。何是如何的何，正是城镇的镇，杰是杰出的杰。",
          expectInsertable: true, mustContain: ["何镇杰"], mustNotContain: ["城镇"]),
    .init(id: "correction-simple",
          transcript: "我们周五下午见吧，哦不对，还是周一上午吧。",
          expectInsertable: true, mustContain: ["周一上午"], mustNotContain: ["周五下午", "不对"]),
    .init(id: "correction-unlisted-cue",
          transcript: "会议定在周三，啊不对，改到周四吧。",
          expectInsertable: true, mustContain: ["周四"], mustNotContain: ["周三"]),
    .init(id: "correction-chain",
          transcript: "会议定在周三。不对，周四。呃不对，还是周五吧。",
          expectInsertable: true, mustContain: ["周五"], mustNotContain: ["周三", "周四"]),
    .init(id: "correction-mixed-en",
          transcript: "send the report to Kevin，呃不对，send it to Michael instead。",
          expectInsertable: true, mustContain: ["Michael"], mustNotContain: ["Kevin"]),
    .init(id: "side-note",
          transcript: "给老板发消息说我明天上午请个假，这句不用写，我等下自己加称呼。",
          expectInsertable: true, mustContain: ["请个假"], mustNotContain: ["不用写", "自己加称呼"]),
    .init(id: "quoted-negative",
          transcript: "他刚才说\"不对，是周五\"，你记一下这句话。",
          expectInsertable: true, mustContain: ["是周五"], mustNotContain: []),
    .init(id: "prose-negative",
          transcript: "今天下午三点在会议室开项目周会，请大家准时参加。",
          expectInsertable: true, mustContain: ["项目周会"], mustNotContain: []),
    .init(id: "filler-heavy",
          transcript: "那个，我在想，我们是不是可以，就是，找一个便宜一点的方案，但是也要好看一些。",
          expectInsertable: true, mustContain: ["便宜一点的方案"], mustNotContain: []),
]

private struct ProviderUnderTest {
    let name: String
    let endpoint: LLMEndpoint
}

private func env(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
}

private func providersUnderTest() -> [ProviderUnderTest] {
    var providers = [ProviderUnderTest]()
    if let key = env("MIMO_KEY") {
        providers.append(.init(name: "mimo-v2.5", endpoint: LLMEndpoint(
            providerId: "mimo",
            baseURL: env("MIMO_BASEURL") ?? "https://token-plan-cn.xiaomimimo.com/v1",
            model: env("MIMO_MODEL") ?? "mimo-v2.5",
            apiKey: key)))
    }
    if let key = env("QWEN_KEY") {
        providers.append(.init(name: "qwen3.6-flash", endpoint: LLMEndpoint(
            providerId: "qwen",
            baseURL: env("QWEN_BASEURL") ?? "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: env("QWEN_MODEL") ?? "qwen3.6-flash",
            apiKey: key)))
    }
    if let key = env("DEEPSEEK_KEY") {
        providers.append(.init(name: "deepseek-v4-flash", endpoint: LLMEndpoint(
            providerId: "deepseek",
            baseURL: env("DEEPSEEK_BASEURL") ?? "https://api.deepseek.com/v1",
            model: env("DEEPSEEK_MODEL") ?? "deepseek-v4-flash",
            apiKey: key)))
    }
    if let key = env("DOUBAO_KEY") {
        providers.append(.init(name: "doubao-seed-2.1-turbo", endpoint: LLMEndpoint(
            providerId: "doubao",
            baseURL: env("DOUBAO_BASEURL") ?? "https://ark.cn-beijing.volces.com/api/v3",
            model: env("DOUBAO_MODEL") ?? "doubao-seed-2-1-turbo-260628",
            apiKey: key)))
    }
    return providers
}

/// Wraps the real compiler and keeps the last raw plan bytes, so a decode/verify failure can
/// dump the offending JSON (our own eval sentences only — local diagnosis, never committed).
private struct RecordingCompiler: IntentPlanCompiler {
    let inner: DirectIntentPlanAPI
    let box: RawBox
    final class RawBox: @unchecked Sendable { var last: Data? }
    func compile(_ input: IntentCompilerInput) async throws -> Data {
        let data = try await inner.compile(input)
        box.last = data
        return data
    }
}

@Test(.enabled(if: env("RESPONSAY_INTENT_EVAL") == "1"))
func liveEval_weakModelsHoldThePlanContract() async throws {
    let providers = providersUnderTest()
    try #require(!providers.isEmpty, "RESPONSAY_INTENT_EVAL=1 but no provider keys in env")

    final class Sink: @unchecked Sendable { var last: String? }
    let dumpRawOnFailure = env("RESPONSAY_INTENT_EVAL_DUMP") == "1"
    var lines = ["", "=== #575 live eval ==="]
    var failures = [String]()

    for provider in providers {
        var passed = 0
        var soft = 0
        for evalCase in battery {
            let sink = Sink()
            let rawBox = RecordingCompiler.RawBox()
            let pipeline = IntentCompilationPipeline(
                compiler: RecordingCompiler(
                    inner: DirectIntentPlanAPI(endpoint: provider.endpoint), box: rawBox),
                failureSink: { sink.last = $0 })
            let outcome = await pipeline.compile(
                finalTranscript: evalCase.transcript,
                locale: .chinese,
                allowedContext: nil,
                routePolicy: .injectedCompiler)

            // Three-tier verdict (#575 release gate): PASS = auto-inserted correctly;
            // SOFT = stopped in a recoverable review (candidate confirm / safe abstention —
            // one tap, never wrong); HARD = a blocked card or wrong text. Gate: HARD == 0
            // for every provider, auto-insert (PASS) rate ≥ 80%.
            var verdictNotes = [String]()
            var text = ""
            var tier = "PASS"
            switch outcome {
            case let .insertable(output, route):
                text = output
                if !evalCase.expectInsertable { verdictNotes.append("unexpected insertable") }
                for needle in evalCase.mustContain where !output.contains(needle) {
                    verdictNotes.append("missing 「\(needle)」")
                }
                for needle in evalCase.mustNotContain where output.contains(needle) {
                    verdictNotes.append("leaked 「\(needle)」")
                }
                if !verdictNotes.isEmpty { tier = "HARD" }
                _ = route
            case let .needsReview(reason, proposal):
                tier = "SOFT"
                verdictNotes.append("review(\(reason)) candidates=\(proposal?.candidates.count ?? 0)")
            case .safeUnavailable(let reason):
                tier = "HARD"
                verdictNotes.append("safeUnavailable(\(reason.rawValue)) category=\(sink.last ?? "-")")
            }
            switch tier {
            case "PASS": passed += 1
            case "SOFT": soft += 1
            default:
                failures.append("\(provider.name)/\(evalCase.id): \(verdictNotes.joined(separator: "; "))")
            }
            lines.append("[\(provider.name)] \(evalCase.id): \(tier)"
                + (verdictNotes.isEmpty ? "" : " \(verdictNotes.joined(separator: "; "))")
                + (text.isEmpty ? "" : "  →「\(text)」"))
            if tier != "PASS", dumpRawOnFailure, let raw = rawBox.last,
               let json = String(data: raw, encoding: .utf8) {
                lines.append("    RAW: \(json.count <= 900 ? json : String(json.prefix(900)) + "…")")
            }
        }
        let hard = battery.count - passed - soft
        lines.append("[\(provider.name)] auto=\(passed)/\(battery.count) soft=\(soft) hard=\(hard)")
    }
    print(lines.joined(separator: "\n"))
    if let reportPath = env("RESPONSAY_INTENT_EVAL_REPORT") {
        try? lines.joined(separator: "\n").write(
            toFile: reportPath, atomically: true, encoding: .utf8)
    }
    #expect(failures.isEmpty, "\(failures.count) failures:\n\(failures.joined(separator: "\n"))")
}
