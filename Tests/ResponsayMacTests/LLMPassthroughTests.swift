import XCTest
@testable import ResponsayMac
import ResponsayCore

/// #390: when no LLM is configured, light polish degrades to passthrough so dictation
/// stays usable as 纯听写. Explicit rewrite/translate actions must surface setup.
final class LLMPassthroughTests: XCTestCase {
    func testRewriteThrowsWhenNoLLM() async throws {
        let api = SettingsBackedTextRewriteAPI(resolveEndpoint: { nil })
        do {
            _ = try await api.rewrite("把这句改一下", style: .tone(.formal))
            XCTFail("rewrite should require a configured text model")
        } catch {
            XCTAssertEqual(error.localizedDescription, LLMEndpointResolver.notConfigured.localizedDescription)
        }
    }

    func testPolishPassesThroughWhenNoLLM() async throws {
        let api = SettingsBackedTextPolishAPI(resolveEndpoint: { nil })
        let result = try await api.polish("逐字稿没有标点")
        XCTAssertEqual(result.text, "逐字稿没有标点")
        XCTAssertEqual(result.original, "逐字稿没有标点")
    }

    func testTranslateThrowsWhenNoLLM() async throws {
        let api = SettingsBackedTextTranslationAPI(resolveEndpoint: { nil })
        do {
            _ = try await api.translate("hello", target: .englishUS)
            XCTFail("translate should require a configured text model")
        } catch {
            XCTAssertEqual(error.localizedDescription, LLMEndpointResolver.notConfigured.localizedDescription)
        }
    }
}
