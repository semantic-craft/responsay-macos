import ResponsayCore
import XCTest
@testable import ResponsayMac

final class ASRProviderRouteTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ASRProviderRouteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDictationCloudRouteDecision() {
        let cases: [(provider: String, engine: ASREngine, route: ASRProviderRoute)] = [
            ("openai", .cloudOpenAI, .openAI),
            ("mimo", .cloudMimo, .mimo),
            ("qwen-asr-flash", .cloudQwenASRFlashRealtime, .qwenASRFlashRealtime),
            ("volcengine-flash", .cloudVolcengineFlash, .volcengineFlash),
            ("custom", .customOpenAI, .customOpenAI),
        ]

        for item in cases {
            defaults.set(item.provider, forKey: "byok.asr.provider")

            XCTAssertEqual(
                ASRProviderRoute.dictation(
                    selected: item.engine,
                    isInstalled: { _ in true },
                    cloudHasKey: { _ in true }),
                item.route)
        }
    }
}
