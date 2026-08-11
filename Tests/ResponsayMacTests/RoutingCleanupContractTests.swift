import Foundation
import XCTest

/// Keeps retired routing indirection from becoming a second public seam beside the runtime paths.
final class RoutingCleanupContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRetiredLLMResolveCloudFacadeIsAbsent() throws {
        let source = try source(at: "macOS/App/LLMEndpointResolver.swift")

        XCTAssertFalse(source.contains("resolveCloud"))
    }

    func testQwenCaptureReturnsConfigWithoutResolutionWrapper() throws {
        let resolver = try source(at: "macOS/Speech/QwenRunTaskCaptureConfiguration.swift")
        let router = try source(at: "macOS/Speech/RoutedSpeechCaptureService.swift")

        XCTAssertFalse(resolver.contains("struct Resolution"))
        XCTAssertFalse(router.contains("resolution.config"))
    }

    func testASRPlanApplicationHasASROnlyInterface() throws {
        let source = try source(at: "macOS/MainWindow/ModelRouteSelectionActions.swift")

        XCTAssertTrue(source.contains("private static func applyASRPlan("))
        XCTAssertFalse(source.contains("private static func applyPlan("))
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8)
    }
}
