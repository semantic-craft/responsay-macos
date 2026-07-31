import Foundation
import Testing
@testable import ResponsayCore

/// #581 — opt-in LIVE eval for 意图成稿 (the polish lane): the product decision is that this
/// lane carries ~98% of everyday dictation intent (释字、改口、撤回、元指令…), with 校验成稿
/// reserved for verified-or-nothing moments. So the polish prompt gets the same treatment the
/// intent prompt got in #575: a scenario battery over real providers, tuned until weak models
/// hold it too. Gated on `RESPONSAY_POLISH_EVAL=1` + per-provider keys; absent ⇒ SKIPPED.
private struct PolishCase {
    let id: String
    let transcript: String
    let mustContain: [String]
    let mustNotContain: [String]
}

private let battery: [PolishCase] = [
    // 口述释字三型：自证 / 知识型 / 同音纠错 —— 应用线索并删除线索句
    .init(id: "clue-selfevidence",
          transcript: "给我的学生何振杰写一封邮件，何是如何的何，振是城镇的镇，杰是杰出的杰。",
          mustContain: ["何镇杰"], mustNotContain: ["如何的", "城镇的", "杰出的"]),
    .init(id: "clue-knowledge",
          transcript: "我要给我的学生乐馨镁写一封邮件，乐是快乐的乐，馨是温馨的馨，镁是元素周期表那个镁。",
          mustContain: ["乐馨镁"], mustNotContain: ["快乐的", "温馨的", "元素周期表"]),
    .init(id: "clue-mishear-fix",
          transcript: "给乐欣美写个消息，乐是快乐的乐，欣是温馨的馨，美是元素周期表的那个镁。",
          mustContain: ["乐馨镁"], mustNotContain: ["乐欣美", "元素周期表"]),
    // 改口：邻近 / 远距 / 连环 / 撤回整句 / 犹豫后定稿
    .init(id: "correction-adjacent",
          transcript: "我们周五下午见吧，啊不对，还是周一上午吧。",
          mustContain: ["周一上午"], mustNotContain: ["周五下午", "不对"]),
    .init(id: "correction-far",
          transcript: "帮我先订三张周六的票。另外查一下明天北京的天气。刚才说错了，票要订五张。",
          mustContain: ["五张", "天气"], mustNotContain: ["三张"]),
    .init(id: "correction-chain",
          transcript: "会议定在周三。不对，周四。呃不对，还是周五吧。",
          mustContain: ["周五"], mustNotContain: ["周三", "周四"]),
    .init(id: "retract-sentence",
          transcript: "跟他说合同已经寄出去了。等等，这句先别写，就说合同这周内一定寄出。",
          mustContain: ["这周内"], mustNotContain: ["已经寄出", "别写"]),
    .init(id: "option-settle",
          transcript: "文档标题要么叫周报，要么叫工作总结……嗯，还是叫周报吧。",
          mustContain: ["周报"], mustNotContain: ["工作总结"]),
    // 元指令：执行并删除
    .init(id: "meta-tone",
          transcript: "帮我回复他：今晚的评审会我参加。语气客气一点。",
          mustContain: ["参加"], mustNotContain: ["语气", "客气一点"]),
    .init(id: "append-later",
          transcript: "通知大家明天上午九点开会。对了，再加一句：记得带电脑。",
          mustContain: ["点", "带电脑"], mustNotContain: ["再加一句"]),   // 九点/9点 both fine
    // 保护：引号 / 数字单号 / 语气不拔高
    .init(id: "quote-guard",
          transcript: "他刚才说\"不对，是周五\"，你记一下这句话。",
          mustContain: ["不对，是周五"], mustNotContain: []),
    .init(id: "number-protect",
          transcript: "订单号是20260714，金额是三千五百元，别搞错了。",
          mustContain: ["20260714", "3500"], mustNotContain: []),
    .init(id: "hedge-keep",
          transcript: "我觉得这个方案吧，大概可以。",
          mustContain: ["大概"], mustNotContain: ["基本可行", "经过分析"]),
    // 清理与重组
    .init(id: "filler-reframe",
          transcript: "那个，我在想，我们是不是可以，就是，找一个便宜一点的方案，但是也要好看一些。",
          mustContain: ["方案"], mustNotContain: ["那个，", "就是，"]),
    .init(id: "list-format",
          transcript: "明天要做三件事，第一去银行办手续，第二给客户回电话，第三把季度报告写完。",
          mustContain: ["银行", "回电话", "季度报告"], mustNotContain: []),
    .init(id: "tech-asr-fix",
          transcript: "把阿屁艾的脱肯重新申请一下，然后把配置提交到跟目录。",
          mustContain: ["API", "Token", "根目录"], mustNotContain: ["阿屁艾", "脱肯", "跟目录"]),
    .init(id: "en-mixed-correction",
          transcript: "send the report to Kevin，呃不对，发给 Michael。",
          mustContain: ["Michael"], mustNotContain: ["Kevin"]),
    .init(id: "prose-noop",
          transcript: "今天下午三点在会议室开项目周会，请大家准时参加。",
          mustContain: ["项目周会", "准时参加"], mustNotContain: []),
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
    if let key = env("DEEPSEEK_KEY") {
        providers.append(.init(name: "deepseek-v4-flash", endpoint: LLMEndpoint(
            providerId: "deepseek", baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-v4-flash", apiKey: key)))
    }
    if let key = env("QWEN_KEY") {
        providers.append(.init(name: "qwen3.7-flash", endpoint: LLMEndpoint(
            providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen3.7-flash", apiKey: key)))
    }
    if let key = env("DOUBAO_KEY") {
        providers.append(.init(name: "doubao-seed-2.1-turbo", endpoint: LLMEndpoint(
            providerId: "doubao", baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: "doubao-seed-2-1-turbo-260628", apiKey: key)))
    }
    if let key = env("MIMO_KEY") {
        providers.append(.init(name: "mimo-v2.5", endpoint: LLMEndpoint(
            providerId: "mimo", baseURL: "https://token-plan-cn.xiaomimimo.com/v1",
            model: "mimo-v2.5", apiKey: key)))
    }
    if let key = env("MINIMAX_KEY") {
        providers.append(.init(name: "minimax-m2.7", endpoint: LLMEndpoint(
            providerId: "minimax", baseURL: "https://api.minimaxi.com/v1",
            model: "MiniMax-M2.7-highspeed", apiKey: key)))
    }
    return providers
}

@Test(.enabled(if: env("RESPONSAY_POLISH_EVAL") == "1"))
func liveEval_polishCarriesEverydayIntent() async throws {
    let providers = providersUnderTest()
    try #require(!providers.isEmpty, "RESPONSAY_POLISH_EVAL=1 but no provider keys in env")

    var lines = ["", "=== #581 polish live eval ==="]
    var failures = [String]()

    for provider in providers {
        var passed = 0
        for polishCase in battery {
            var notes = [String]()
            var text = ""
            do {
                let result = try await DirectTextPolishAPI(endpoint: provider.endpoint)
                    .polish(polishCase.transcript)
                text = result.text
                for needle in polishCase.mustContain where !text.contains(needle) {
                    notes.append("missing 「\(needle)」")
                }
                for needle in polishCase.mustNotContain where text.contains(needle) {
                    notes.append("leaked 「\(needle)」")
                }
            } catch let error as LLMError {
                notes.append("error: \(error)")
            } catch {
                notes.append("error: \(type(of: error))")
            }
            if notes.isEmpty { passed += 1 } else {
                failures.append("\(provider.name)/\(polishCase.id): \(notes.joined(separator: "; "))")
            }
            lines.append("[\(provider.name)] \(polishCase.id): \(notes.isEmpty ? "PASS" : "FAIL \(notes.joined(separator: "; "))")"
                + (text.isEmpty ? "" : "  →「\(text.prefix(80))」"))
        }
        lines.append("[\(provider.name)] \(passed)/\(battery.count) passed")
    }
    print(lines.joined(separator: "\n"))
    if let reportPath = env("RESPONSAY_POLISH_EVAL_REPORT") {
        try? lines.joined(separator: "\n").write(
            toFile: reportPath, atomically: true, encoding: .utf8)
    }
    #expect(failures.isEmpty, "\(failures.count) failures:\n\(failures.joined(separator: "\n"))")
}
