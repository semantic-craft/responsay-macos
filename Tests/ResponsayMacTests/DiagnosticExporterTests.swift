import XCTest
@testable import ResponsayMac

@MainActor
final class DiagnosticExporterTests: XCTestCase {
    private var saved: [String: Any?] = [:]
    private let keys = [
        ASREngine.defaultsKey,
        TTSEngine.defaultsKey,
        "byok.asr.provider",
        "byok.asr.mimo.region",
        "byok.asr.mimo.plan",
        "byok.asr.mimo.model",
        "byok.asr.mimo.baseURL",
        "byok.asr.openai.baseURL",
        "byok.tts.provider",
        "byok.llm.provider",
    ]

    override func setUp() {
        super.setUp()
        saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for key in keys {
            if let value = saved[key] ?? nil {
                d.set(value, forKey: key)
            } else {
                d.removeObject(forKey: key)
            }
        }
        saved = [:]
        super.tearDown()
    }

    private func collectDiagnostics() -> [String: Any] {
        DiagnosticExporter.collectDiagnostics(
            dispatcher: ProviderConfigDispatcher(keyReader: { _ in nil }))
    }

    func testDiagnosticsReportsCurrentAppDirectASRConfig() {
        let d = UserDefaults.standard
        d.set(ASREngine.cloudMimo.rawValue, forKey: ASREngine.defaultsKey)
        d.set("mimo", forKey: "byok.asr.provider")
        d.set(ProviderRegion.china.rawValue, forKey: "byok.asr.mimo.region")
        d.set(BillingPlan.package.rawValue, forKey: "byok.asr.mimo.plan")
        d.set("mimo-v2.5-asr", forKey: "byok.asr.mimo.model")
        d.set("https://token-plan-cn.xiaomimimo.com/v1", forKey: "byok.asr.mimo.baseURL")

        let payload = collectDiagnostics()
        let asr = payload["config_asr_active"] as? [String: Any]

        XCTAssertEqual(asr?["engine"] as? String, ASREngine.cloudMimo.rawValue)
        XCTAssertEqual(asr?["provider"] as? String, "mimo")
        XCTAssertEqual(asr?["model"] as? String, "mimo-v2.5-asr")
        XCTAssertEqual(asr?["baseURL"] as? String, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(payload["backend_health"] as? String, "Retired / App-Direct")
    }

    func testDiagnosticsReportsLocalASRAsActiveEvenWhenCloudProfileIsConfigured() {
        let d = UserDefaults.standard
        d.set(ASREngine.sensevoiceLocal.rawValue, forKey: ASREngine.defaultsKey)
        d.set("mimo", forKey: "byok.asr.provider")
        d.set(ProviderRegion.china.rawValue, forKey: "byok.asr.mimo.region")
        d.set(BillingPlan.package.rawValue, forKey: "byok.asr.mimo.plan")
        d.set("mimo-v2.5-asr", forKey: "byok.asr.mimo.model")
        d.set("https://token-plan-cn.xiaomimimo.com/v1", forKey: "byok.asr.mimo.baseURL")

        let payload = collectDiagnostics()
        let active = payload["config_asr_active"] as? [String: Any]
        let savedCloud = payload["config_asr_saved_cloud"] as? [String: Any]

        XCTAssertEqual(active?["engine"] as? String, ASREngine.sensevoiceLocal.rawValue)
        XCTAssertEqual(active?["providerMode"] as? String, "local")
        XCTAssertEqual(active?["provider"] as? String, "local")
        XCTAssertNil(active?["baseURL"])
        XCTAssertEqual(savedCloud?["provider"] as? String, "mimo")
        XCTAssertEqual(savedCloud?["baseURL"] as? String, "https://token-plan-cn.xiaomimimo.com/v1")
    }

    func testDiagnosticsResolveActiveCloudEngineOverStaleASRProviderProfile() {
        let d = UserDefaults.standard
        d.set(ASREngine.cloudMimo.rawValue, forKey: ASREngine.defaultsKey)
        d.set("openai", forKey: "byok.asr.provider")
        d.set("https://api.openai.com/v1", forKey: "byok.asr.openai.baseURL")

        let payload = collectDiagnostics()
        let active = payload["config_asr_active"] as? [String: Any]

        XCTAssertEqual(active?["engine"] as? String, ASREngine.cloudMimo.rawValue)
        XCTAssertEqual(active?["providerMode"] as? String, "cloud")
        XCTAssertEqual(active?["provider"] as? String, "mimo")
        XCTAssertEqual(active?["baseURL"] as? String, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(active?["model"] as? String, "mimo-v2.5-asr")
    }
}
