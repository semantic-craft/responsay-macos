import Testing
import Foundation
@testable import ResponsayCore

// Own stub class + static state, so the actions e2e suites never race the rewrite suite's
// LLMStubURLProtocol.
final class LLMActionsStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
        Self.requestBody = request.httpBody ?? Self.readStream(request.httpBodyStream)
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func readStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private func actionsStubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [LLMActionsStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

private func completion(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
}

private func cloudEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "openai", baseURL: "https://api.openai.com/v1",
                model: "gpt-4.1", apiKey: "sk-1", thinkingEnabled: false)
}

private func mimoSearchEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "mimo", baseURL: "https://api.xiaomimimo.com/v1",
                model: "mimo-v2.5", apiKey: "sk-1", thinkingEnabled: false)
}

private func qwenSearchEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                model: "qwen-plus", apiKey: "sk-1", thinkingEnabled: false)
}

private func doubaoSearchEndpoint() -> LLMEndpoint {
    LLMEndpoint(providerId: "doubao", baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                model: "doubao-seed-2-0-lite-260428", apiKey: "ark-test-key", thinkingEnabled: false)
}

// MARK: - 241 Translate

struct TranslatePromptBuilderTests {
    @Test func namesTargetAndCarriesText() {
        let p = TranslatePromptBuilder.build(text: "我看看", target: .englishUS)
        #expect(p.system.contains("American English"))
        #expect(p.user.contains("我看看"))
        #expect(p.user.contains("en-US"))
        #expect(TranslatePromptBuilder.build(text: "x", target: .german).system.contains("German"))
    }

    @Test func translationPromptIsFaithfulLiteral() {
        let p = TranslatePromptBuilder.build(text: "我看看", target: .englishUS)

        #expect(p.system.contains("Preserve meaning, names, citations"))
        #expect(p.system.contains("faithfully, accurately, and as literally"))
        #expect(p.system.contains("Preserve source wording and sentence structure"))
        #expect(p.system.contains("Do not rewrite for idiomatic/native expression"))
        #expect(p.system.contains("Do not return alternatives, teaching notes, or explanation"))
        #expect(!p.system.contains("fluent target-language/locale speaker"))
        #expect(!p.system.contains("single best natural wording"))
    }
}

// MARK: - 242 Express

struct ExpressPromptBuilderTests {
    @Test func registerDirectivesAreDistinct() {
        let regs: [CoachRegister] = [.casual, .neutral, .formal, .academic]
        #expect(Set(regs.map { ExpressPromptBuilder.coachRegisterDirective($0) }).count == 4)
        #expect(ExpressPromptBuilder.coachRegisterDirective(.academic).contains("学术"))
    }

    @Test func contextLines_respectBudgetAndPriority() {
        let ctx = ExpressionContext(
            appName: "TextEdit", selectedText: "the attached brief", hotwords: ["CLSCI"])
        let lines = ExpressPromptBuilder.contextLines(ctx)
        #expect(lines.first?.contains("the attached brief") == true)   // highest priority first
        #expect(lines.contains { $0.contains("CLSCI") })
        #expect(ExpressPromptBuilder.contextLines(nil).isEmpty)
    }

    @Test func build_putsRegisterAndUtteranceIn() {
        let p = ExpressPromptBuilder.build(intent: "please give me some advices", context: nil, register: .academic)
        #expect(p.system.contains("学术"))
        #expect(p.user.contains("please give me some advices"))
        #expect(p.system.contains("{\"idiomatic\": string"))
    }

    @Test func optimizedExpressPromptIsPrimarilyEnglishToIdiomaticEnglish() {
        let p = ExpressPromptBuilder.build(intent: "please give me some advices", context: nil, register: .casual)

        #expect(p.system.contains("bilingual foreign-language coach"))
        #expect(p.system.contains("Target:\nidiomatic spoken American English"))
        #expect(p.system.contains("target language/locale is en-US (American English)"))
        #expect(p.system.contains("If it is ALREADY idiomatic and natural in American English"))
        #expect(p.user.contains("Target language/locale: en-US (American English)"))
        #expect(p.user.contains("Do not mirror source wording"))
    }

    @Test func build_carriesSelectedTargetLanguage() {
        let p = ExpressPromptBuilder.build(
            intent: "ich will das freundlich sagen",
            context: nil,
            register: .neutral,
            target: .german)

        #expect(p.system.contains("target language/locale is de-DE (German)"))
        #expect(p.system.contains("idiomatic spoken German"))
        #expect(p.user.contains("Target language/locale: de-DE (German)"))
    }

    // 419 — English input is two-tier: already-idiomatic → light touch-ups; rough/broken →
    // rebuild the whole sentence from scratch (don't patch the broken structure).
    @Test func build_englishInput_hasTwoTierRebuildRule() {
        let p = ExpressPromptBuilder.build(intent: "you can level your English into medium", context: nil, register: .casual)
        #expect(p.system.contains("rebuild the whole sentence from scratch"))
        #expect(p.system.contains("light touch-ups"))
    }

    // 420 — 改写策略 is a distinct directive; guessIntent adds intent reconstruction + brakes,
    // faithful does not. Default (no strategy arg) is faithful.
    @Test func strategyDirectivesAreDistinct() {
        #expect(ExpressPromptBuilder.strategyDirective(.faithful)
            != ExpressPromptBuilder.strategyDirective(.guessIntent))
        #expect(ExpressPromptBuilder.strategyDirective(.faithful).contains("忠实改写"))
        #expect(ExpressPromptBuilder.strategyDirective(.guessIntent).contains("猜测意图"))
    }

    @Test func build_guessIntent_carriesReconstructionAndBrakes() {
        let p = ExpressPromptBuilder.build(
            intent: "i want say the thing", context: nil, register: .casual, strategy: .guessIntent)
        #expect(p.system.contains("reconstruct the single most likely"))
        #expect(p.system.contains("fall back to a faithful upgrade"))
    }

    @Test func build_faithfulIsDefault_andHasNoReconstruction() {
        let dflt = ExpressPromptBuilder.build(intent: "x", context: nil, register: .casual)
        let faithful = ExpressPromptBuilder.build(intent: "x", context: nil, register: .casual, strategy: .faithful)
        #expect(dflt.system == faithful.system)
        #expect(!faithful.system.contains("reconstruct the single most likely"))
    }

    // 422 — the express output schema carries an intentNote field for the 猜测意图 reconstruction.
    @Test func build_outputSchema_includesIntentNote() {
        let p = ExpressPromptBuilder.build(intent: "x", context: nil, register: .casual, strategy: .guessIntent)
        #expect(p.system.contains("\"intentNote\""))
    }

    // A/B pin (2026-06-16) — guards the 419 failure mode: a 档位's directive existed but a parallel
    // (streaming) code path bypassed it, so the tier never reached the model. These prove that the
    // single live `build()` path injects EXACTLY the selected 语气 / 改写策略 and nothing else —
    // i.e. every tier genuinely takes effect. (Markers are the unique `(label / …` prefixes; bare
    // labels like 口语 also appear in the thinkingShift block, so they cannot be exclusivity markers.)
    @Test func build_injectsExactlyTheSelectedRegister() {
        let markers: [CoachRegister: String] = [
            .casual: "(口语 / casual spoken",
            .neutral: "(中性 / neutral spoken",
            .formal: "(正式 / formal spoken",
            .academic: "(学术 / spoken academic",
        ]
        for (register, own) in markers {
            let system = ExpressPromptBuilder.build(intent: "x", context: nil, register: register).system
            #expect(system.contains(own))
            for (other, otherMarker) in markers where other != register {
                #expect(!system.contains(otherMarker))
            }
        }
    }

    @Test func build_injectsExactlyTheSelectedStrategy() {
        let faithfulMarker = "(忠实改写 / faithful"
        let guessMarker = "(猜测意图 / guess-intent"
        let faithful = ExpressPromptBuilder.build(
            intent: "x", context: nil, register: .casual, strategy: .faithful).system
        let guess = ExpressPromptBuilder.build(
            intent: "x", context: nil, register: .casual, strategy: .guessIntent).system
        #expect(faithful.contains(faithfulMarker))
        #expect(!faithful.contains(guessMarker))
        #expect(guess.contains(guessMarker))
        #expect(!guess.contains(faithfulMarker))
    }

    // 4 语气 × 2 改写策略 = 8 tier combinations must produce materially distinct system prompts —
    // no two 档位 may collapse to the same prompt.
    @Test func build_allEightTierCombosAreDistinct() {
        let registers: [CoachRegister] = [.casual, .neutral, .formal, .academic]
        let strategies: [ExpressRewriteStrategy] = [.faithful, .guessIntent]
        let systems = registers.flatMap { r in
            strategies.map { s in
                ExpressPromptBuilder.build(intent: "x", context: nil, register: r, strategy: s).system
            }
        }
        #expect(systems.count == 8)
        #expect(Set(systems).count == 8)
    }
}

// MARK: - e2e (stubbed transport)

// All network e2e tests share `LLMActionsStubURLProtocol`'s static state, so they live in ONE
// serialized suite — separate `.serialized` suites would still run in parallel and race.
@Suite(.serialized)
struct DirectActionsE2ETests {
    @Test func translate_parsesEnvelope_setsTargetAndOriginal() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"text":"Let me check.","notes":["meaning-first"]}"#)
        let api = DirectTextTranslationAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let r = try await api.translate("我看看", target: .englishUS)
        #expect(r.text == "Let me check.")
        #expect(r.original == "我看看")
        #expect(r.targetLanguage == "en-US")
        #expect(r.notes == ["meaning-first"])
    }

    // 表达升级's bundled skill (`expression_upgrade.cn`) instructs PLAIN-TEXT output ("直接输出
    // 最终正文…纯文本…不加代码围栏"), which fights the {text,changes} envelope the assembler
    // forces. A fast model (e.g. deepseek-v4-flash) that obeys the skill returns plain text;
    // rewrite must accept it (same fallback as 轻改写) instead of throwing badJSON and dropping
    // the whole rewrite — that would silently fail 表达升级 and keep the verbatim transcript.
    @Test func rewrite_toleratesPlainTextReply() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion("这个方案整体可行，性能还需再打磨。")
        let api = DirectTextRewriteAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let r = try await api.rewrite("这个方案大概可以就是性能再看看", style: .tone(.natural))
        #expect(r.text == "这个方案整体可行，性能还需再打磨。")
        #expect(r.original == "这个方案大概可以就是性能再看看")
        #expect(r.changes.isEmpty)
    }

    // The {text,changes} envelope path still works when the model complies (no regression).
    @Test func rewrite_parsesJSONEnvelopeWhenPresent() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"text":"重述后的句子。","changes":["重组句式"]}"#)
        let api = DirectTextRewriteAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let r = try await api.rewrite("原句", style: .tone(.natural))
        #expect(r.text == "重述后的句子。")
        #expect(r.changes == ["重组句式"])
    }

    @Test func express_parsesAllFields_originalFromIntent() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"idiomatic":"Could you give me some pointers?","alternatives":["Any tips?"],"reasons":["更口语"],"thinkingShift":"中式名词堆叠 / 美式动词请求"}"#)
        let api = DirectCoachAPI(endpoint: cloudEndpoint(), register: .casual, session: actionsStubSession())
        let r = try await api.express("please give me some advices")
        #expect(r.idiomatic == "Could you give me some pointers?")
        #expect(r.original == "please give me some advices")
        #expect(r.alternatives == ["Any tips?"])
        #expect(r.thinkingShift.contains("美式"))
    }

    // 422 — 猜测意图 reconstruction surfaces as parsed `intentNote`.
    @Test func express_parsesIntentNote() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(
            #"{"idiomatic":"Bring it up to a native level.","reasons":["r"],"intentNote":"原话「medium」→ 我理解为 native"}"#)
        let api = DirectCoachAPI(
            endpoint: cloudEndpoint(), register: .casual, strategy: .guessIntent, session: actionsStubSession())
        let r = try await api.express("you can level into medium")
        #expect(r.intentNote.contains("native"))
    }

    // 243 legal: the assembled prompt is sent to the provider; the raw model text becomes
    // `output` for the validator (the backend route was a pure passthrough).
    @Test func legal_executesAndReturnsRawOutputWithRunId() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion(#"{"cardType":"draft","text":"本段建议……[待核]"}"#)
        let exec = DirectLegalSkillExecutorAPI(
            endpoint: cloudEndpoint(), session: actionsStubSession(), runIdProvider: { "run-1" })
        let request = LegalSkillExecutionRequest(
            skillId: "legal.report.case", systemPrompt: "SYS", userPrompt: "USR", modelRoute: .cloudAllowed)
        let resp = try await exec.executeSkill(request)
        #expect(resp.output == #"{"cardType":"draft","text":"本段建议……[待核]"}"#)
        #expect(resp.runId == "run-1")
        #expect(resp.provider == "openai")
    }

    @Test func legal_localOnlyOnCloudEndpoint_refuses() async throws {
        let exec = DirectLegalSkillExecutorAPI(endpoint: cloudEndpoint(), session: actionsStubSession())
        let request = LegalSkillExecutionRequest(
            skillId: "s", systemPrompt: "S", userPrompt: "U", modelRoute: .localOnly)
        await #expect(throws: LLMError.self) { _ = try await exec.executeSkill(request) }
    }

    @Test func legal_searchVerification_sendsSearchEnabledAndParsesSource() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.requestBody = Data()
        LLMActionsStubURLProtocol.requestURL = nil
        LLMActionsStubURLProtocol.data = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": [
                    "content": "已找到国家法律法规数据库来源。",
                    "search_results": [[
                        "title": "中华人民共和国民法典",
                        "url": "https://flk.npc.gov.cn/detail2.html",
                        "content": "第五百七十七条 当事人一方不履行合同义务..."
                    ]]
                ]
            ]]
        ])
        let exec = DirectLegalSkillExecutorAPI(endpoint: mimoSearchEndpoint(), session: actionsStubSession())
        let anchor = VerificationAnchor(
            id: "law:1", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")

        let source = try await exec.searchVerification(anchor, route: .cloudAllowed)

        #expect(source?.title == "中华人民共和国民法典")
        #expect(source?.url == "https://flk.npc.gov.cn/detail2.html")
        let body = try JSONSerialization.jsonObject(with: LLMActionsStubURLProtocol.requestBody) as? [String: Any]
        let tools = try #require(body?["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "web_search")
        #expect((body?["thinking"] as? [String: Any])?["type"] as? String == "disabled")
    }

    @Test func legal_searchVerification_qwenUsesDashScopeNativeSourceResults() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.requestBody = Data()
        LLMActionsStubURLProtocol.requestURL = nil
        LLMActionsStubURLProtocol.data = try JSONSerialization.data(withJSONObject: [
            "output": [
                "choices": [[
                    "message": [
                        "content": "检索到《民法典》第五百七十七条的官方来源。"
                    ]
                ]],
                "search_info": [
                    "search_results": [
                        [
                            "site_name": "百科",
                            "title": "民法典解读",
                            "url": "https://example.com/minfadian"
                        ],
                        [
                            "site_name": "国家法律法规数据库",
                            "title": "中华人民共和国民法典",
                            "url": "https://flk.npc.gov.cn/detail2.html"
                        ]
                    ]
                ]
            ]
        ])
        let exec = DirectLegalSkillExecutorAPI(endpoint: qwenSearchEndpoint(), session: actionsStubSession())
        let anchor = VerificationAnchor(
            id: "law:1", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")

        let source = try await exec.searchVerification(anchor, route: .cloudAllowed)

        #expect(LLMActionsStubURLProtocol.requestURL?.absoluteString
                == "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
        #expect(source?.title == "中华人民共和国民法典")
        #expect(source?.url == "https://flk.npc.gov.cn/detail2.html")
        #expect(source?.provider == "qwen")
        let body = try JSONSerialization.jsonObject(with: LLMActionsStubURLProtocol.requestBody) as? [String: Any]
        let parameters = try #require(body?["parameters"] as? [String: Any])
        #expect(parameters["enable_search"] as? Bool == true)
        #expect(parameters["result_format"] as? String == "message")
        let options = try #require(parameters["search_options"] as? [String: Any])
        #expect(options["forced_search"] as? Bool == true)
        #expect(options["enable_source"] as? Bool == true)
        #expect(options["search_strategy"] as? String == "max")
    }

    @Test func legal_searchVerification_doubaoUsesArkResponsesWebSearch() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.requestBody = Data()
        LLMActionsStubURLProtocol.requestURL = nil
        LLMActionsStubURLProtocol.data = try JSONSerialization.data(withJSONObject: [
            "output": [
                [
                    "type": "web_search_call",
                    "status": "completed"
                ],
                [
                    "type": "message",
                    "content": [[
                        "type": "output_text",
                        "text": "检索到《民法典》第五百七十七条的官方来源。",
                        "annotations": [[
                            "type": "url_citation",
                            "title": "中华人民共和国民法典",
                            "url": "https://flk.npc.gov.cn/detail2.html",
                            "summary": "第五百七十七条 当事人一方不履行合同义务..."
                        ]]
                    ]]
                ]
            ]
        ])
        let exec = DirectLegalSkillExecutorAPI(endpoint: doubaoSearchEndpoint(), session: actionsStubSession())
        let anchor = VerificationAnchor(
            id: "law:1", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")

        let source = try await exec.searchVerification(anchor, route: .cloudAllowed)

        #expect(LLMActionsStubURLProtocol.requestURL?.absoluteString
                == "https://ark.cn-beijing.volces.com/api/v3/responses")
        #expect(source?.title == "中华人民共和国民法典")
        #expect(source?.url == "https://flk.npc.gov.cn/detail2.html")
        #expect(source?.provider == "doubao")
        let body = try JSONSerialization.jsonObject(with: LLMActionsStubURLProtocol.requestBody) as? [String: Any]
        let tools = try #require(body?["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(tools.first?["max_keyword"] as? Int == 2)
        #expect(tools.first?["limit"] as? Int == 3)
        #expect(body?["messages"] == nil)
    }

    // 240 Validate: a real chat call succeeds (returns reply) and surfaces HTTP errors.
    @Test func connectivityCheck_returnsReply_andThrowsOnHTTPError() async throws {
        LLMActionsStubURLProtocol.status = 200
        LLMActionsStubURLProtocol.data = completion("OK")
        let reply = try await LLMConnectivityCheck.validate(endpoint: cloudEndpoint(), session: actionsStubSession())
        #expect(reply == "OK")

        LLMActionsStubURLProtocol.status = 401
        LLMActionsStubURLProtocol.data = #"{"error":"bad key"}"#.data(using: .utf8)!
        await #expect(throws: LLMError.self) {
            _ = try await LLMConnectivityCheck.validate(endpoint: cloudEndpoint(), session: actionsStubSession())
        }
    }
}
