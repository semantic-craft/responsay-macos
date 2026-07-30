import Foundation
import XCTest
@testable import ResponsayCore
@testable import ResponsayMac

/// Opt-in real-service acceptance for the exact Qwen path the app ships.
///
/// The API key is read from the app's existing Keychain slot. The Workspace ID is accepted only
/// through the test process environment or a dedicated temporary test domain, so neither value is
/// embedded in source or persisted by the test. Normal local/CI runs skip this suite.
final class QwenResponsesLiveTests: XCTestCase {
    func testOrdinaryAndWebSearchResponsesAgainstWorkspaceEndpoint() async throws {
        let environment = ProcessInfo.processInfo.environment
        let liveDefaultsName = "com.semanticcraft.responsay.qwen-live-test"
        let liveDefaults = try XCTUnwrap(UserDefaults(suiteName: liveDefaultsName))
        guard environment["RESPONSAY_QWEN_LIVE"] == "1" || liveDefaults.bool(forKey: "enabled") else {
            throw XCTSkip("Set RESPONSAY_QWEN_LIVE=1 to run the Qwen live acceptance.")
        }
        defer { liveDefaults.removePersistentDomain(forName: liveDefaultsName) }
        let workspaceID = try XCTUnwrap(
            environment["QWEN_WORKSPACE_ID"] ?? liveDefaults.string(forKey: "workspaceID"))
        let baseURL = try XCTUnwrap(
            QwenWorkspaceEndpoint.baseURL(workspaceID: workspaceID, region: .china))
        let apiKey = try XCTUnwrap(BYOKKeychain.read("byok.qwen"))
        let model = environment["QWEN_MODEL"]
            ?? ProviderCatalog.qwen.defaultModels[.llm]
            ?? "qwen3.7-flash"
        let endpoint = LLMEndpoint(
            providerId: "qwen",
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            thinkingEnabled: false)
        let client = LLMChatClient()

        let ordinaryRequest = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: "严格按用户要求简短回答。",
            user: "只回答 OK。",
            generationAction: .connectivity,
            timeout: 120)
        try assertPrivateResponsesShape(ordinaryRequest, expectsSearch: false)
        let ordinaryText = try await client.execute(ordinaryRequest)
        XCTAssertFalse(ordinaryText.isEmpty)

        let searchRequest = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: "使用联网搜索，并返回可核验来源。",
            user: "搜索阿里云百炼 Responses API 官方文档，概括其用途。",
            searchEnabled: true,
            generationAction: .ask,
            timeout: 120)
        try assertPrivateResponsesShape(searchRequest, expectsSearch: true)
        let searchData = try await client.executeRaw(searchRequest)
        XCTAssertNotNil(
            LLMSearchResultParser.parse(responseData: searchData, providerId: "qwen"),
            "Qwen web_search completed without a parseable source URL")
    }

    private func assertPrivateResponsesShape(
        _ request: URLRequest,
        expectsSearch: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(request.url?.lastPathComponent, "responses", file: file, line: line)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any],
            file: file,
            line: line)
        XCTAssertEqual(body["store"] as? Bool, false, file: file, line: line)
        XCTAssertNotNil(body["input"], file: file, line: line)
        XCTAssertNil(body["messages"], file: file, line: line)
        XCTAssertNil(body["top_p"], file: file, line: line)

        if expectsSearch {
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]], file: file, line: line)
            XCTAssertEqual(tools.first?["type"] as? String, "web_search", file: file, line: line)
            XCTAssertEqual(body["tool_choice"] as? String, "required", file: file, line: line)
        } else {
            XCTAssertNil(body["tools"], file: file, line: line)
            XCTAssertNil(body["tool_choice"], file: file, line: line)
        }
    }
}
