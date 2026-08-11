import XCTest
@testable import ResponsayMac

/// 猎虫① H1: the backend-era "本机离线 (通义千问)" engine (issues 012/013) survived
/// the 090 backend deletion as a live picker entry whose transcription always
/// died against the deleted localhost:8787. Retired like the other stale
/// entries: deleted from the picker and type surface.
final class ASREngineMigrationTests: XCTestCase {
    private let key = ASREngine.defaultsKey
    private var savedRawValue: String?

    override func setUp() {
        super.setUp()
        savedRawValue = UserDefaults.standard.string(forKey: key)
    }

    override func tearDown() {
        if let savedRawValue {
            UserDefaults.standard.set(savedRawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testDeletedEnginesNoLongerResolve() {
        // #386 (no legacy users): the streaming Zipformer and the backend-era offline
        // Qwen entry were deleted outright (no migration). Their raw values resolve to
        // nil, and a stale stored value falls back to the cold-start default —
        // 千问实时 (2026-07-04), no longer Apple.
        XCTAssertNil(ASREngine(rawValue: "offline-zipformer-streaming"))
        XCTAssertNil(ASREngine(rawValue: "offline-qwen-asr"))
        XCTAssertNil(ASREngine(rawValue: "cloud-qwen-realtime"))
        XCTAssertNil(ASREngine(rawValue: "cloud-qwen"))
        XCTAssertNil(ASREngine(rawValue: "cloud-fun-asr-whole"))
        XCTAssertNil(ASREngine(rawValue: "cloud-qwen-asr-flash"))
        XCTAssertNil(ASREngine(rawValue: "cloud-zhipu"))
        UserDefaults.standard.set("offline-qwen-asr", forKey: key)
        XCTAssertEqual(ASREngine.selected, .cloudQwenASRFlashRealtime)
        UserDefaults.standard.set("cloud-zhipu", forKey: key)
        XCTAssertEqual(ASREngine.selected, .cloudQwenASRFlashRealtime)
    }

    func testColdStartDefaultIsQwenRealtime() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(ASREngine.selected, .cloudQwenASRFlashRealtime)
    }

    func testDeletedVolcengineHTTPBatchEngineNoLongerResolves() {
        XCTAssertNil(ASREngine(rawValue: "cloud-volcengine-flash"))
        UserDefaults.standard.set("cloud-volcengine-flash", forKey: key)
        XCTAssertEqual(ASREngine.selected, .cloudQwenASRFlashRealtime)
    }

    func testCloudProviderSelectionMapsToRuntimeEngine() {
        XCTAssertEqual(ASREngine.cloudEngine(forProviderId: "mimo"), .cloudMimo)
        XCTAssertEqual(ASREngine.cloudEngine(forProviderId: "qwen-asr-flash"), .cloudQwenASRFlashRealtime)
        XCTAssertEqual(ASREngine.cloudEngine(forProviderId: "volcengine-flash"), .cloudVolcengineRealtime)
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "qwen-fun-asr"))
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "qwen-fun-asr-realtime"))
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "qwen"))
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "zhipu"))
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "volc-asr"))
        XCTAssertEqual(ASREngine.cloudEngine(forProviderId: "custom"), .customOpenAI)
        XCTAssertNil(ASREngine.cloudEngine(forProviderId: "apple"))
    }

    func testRetiredProviderPresetIsGone() {
        XCTAssertFalse(
            ProviderCatalog.all.contains { $0.id == "offline-qwen-asr" },
            "no credential-card/preset surface should advertise the retired engine")
    }

    func testEveryCurrentRawValueResolvesToASelectableEngine() {
        for engine in ASREngine.allCases {
            UserDefaults.standard.set(engine.rawValue, forKey: key)
            XCTAssertTrue(
                ASREngine.selectableCases.contains(ASREngine.selected),
                "stale raw value \(engine.rawValue) resolved off the picker roster")
        }
    }
}
