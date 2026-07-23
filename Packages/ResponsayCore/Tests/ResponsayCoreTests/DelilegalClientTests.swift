import Testing
import Foundation
@testable import ResponsayCore

// 得理(Delilegal)检索 client：请求构造（双端点代）+ 响应解码。BYOK key 由调用方传入。
// 真实网络调用 = T3/HITL；本套只测可单测的契约面。
@Suite("DelilegalClient")
struct DelilegalClientTests {
    let ctx = DelilegalRequestContext(sessionId: "sess-1", skillId: "case-retrieval", skillVersion: "1.0.9")

    @Test("新版 skill 端点 + condition.keywords + 鉴权/遥测头")
    func skillCaseKeyword() throws {
        let client = DelilegalClient(apiKey: "sk-test", generation: .skill)
        let req = client.buildRequest(resource: .caseList, context: ctx,
                                      keywords: ["民间借贷 利率上限"], page: 1, size: 10)
        #expect(req.url?.absoluteString == "https://platform.delilegal.com/api/v1/skill/case/list")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(req.value(forHTTPHeaderField: "Session-Id") == "sess-1")
        #expect(req.value(forHTTPHeaderField: "Skill-Id") == "case-retrieval")
        #expect(req.value(forHTTPHeaderField: "Skill-Version") == "1.0.9")
        let body = try JSONSerialization.jsonObject(with: #require(req.httpBody)) as! [String: Any]
        let cond = body["condition"] as! [String: Any]
        #expect((cond["keywords"] as! [String]) == ["民间借贷 利率上限"])
        #expect(body["pageNo"] as? Int == 1)
        #expect(body["pageSize"] as? Int == 10)
        #expect(body["query"] == nil)  // 新版无扁平 query
    }

    @Test("旧版 generice 端点 + 扁平 query（无 condition 嵌套）")
    func gericeCaseQuery() throws {
        let client = DelilegalClient(apiKey: "sk-test", generation: .generice)
        let req = client.buildRequest(resource: .caseList, context: ctx, keywords: ["小产权房"], page: 1, size: 5)
        #expect(req.url?.absoluteString == "https://platform.delilegal.com/api/v1/generice/case/list")
        let body = try JSONSerialization.jsonObject(with: #require(req.httpBody)) as! [String: Any]
        #expect(body["query"] as? String == "小产权房")
        #expect(body["condition"] == nil)
    }

    @Test("语义检索 → condition.fieldName=semantic（法规端点）")
    func semanticLaw() throws {
        let client = DelilegalClient(apiKey: "k", generation: .skill)
        let req = client.buildRequest(resource: .lawList, context: ctx,
                                      keywords: ["竞业限制 补偿"], semantic: true, page: 1, size: 5)
        #expect(req.url?.absoluteString == "https://platform.delilegal.com/api/v1/skill/law/list")
        let body = try JSONSerialization.jsonObject(with: #require(req.httpBody)) as! [String: Any]
        let cond = body["condition"] as! [String: Any]
        #expect(cond["fieldName"] as? String == "semantic")
    }

    @Test("长文本 → condition.longText（新版）/ longText（旧版）")
    func longText() throws {
        let skill = DelilegalClient(apiKey: "k", generation: .skill)
        let req1 = skill.buildRequest(resource: .caseList, context: ctx, longText: "案情……", page: 1, size: 5)
        let b1 = try JSONSerialization.jsonObject(with: #require(req1.httpBody)) as! [String: Any]
        #expect((b1["condition"] as! [String: Any])["longText"] as? String == "案情……")
    }

    @Test("响应解码（标准结构）")
    func decode() throws {
        let json = #"""
        {"success":true,"code":0,"msg":"ok","body":{"data":[{"title":"某案","caseNumber":"(2021)粤03民终1号","court":"某院"}],"totalCount":42}}
        """#.data(using: .utf8)!
        let resp = try DelilegalClient.decode(json)
        #expect(resp.success == true)
        #expect(resp.body?.totalCount == 42)
        #expect(resp.body?.data.first?.title == "某案")
        #expect(resp.body?.data.first?.caseNumber == "(2021)粤03民终1号")
        #expect(resp.body?.data.first?.court == "某院")
    }
}
