import XCTest
@testable import ResponsayMac

/// 280 — one region write drives the sherpa mirror download chain
/// (localMirror → LocalModelDownloader.orderedURLs).
final class NetworkRegionTests: XCTestCase {
    private var savedRegion: String?
    private var savedMirror: String?

    override func setUp() {
        super.setUp()
        savedRegion = UserDefaults.standard.string(forKey: NetworkRegion.defaultsKey)
        savedMirror = UserDefaults.standard.string(forKey: "localMirror")
    }

    override func tearDown() {
        restore(savedRegion, key: NetworkRegion.defaultsKey)
        restore(savedMirror, key: "localMirror")
        super.tearDown()
    }

    private func restore(_ value: String?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private let fixtureURLs = [
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/a/m.tar.bz2")!,
        URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/x/m.tar.bz2")!,
        URL(string: "https://ghfast.top/https://github.com/k2-fsa/x/m.tar.bz2")!,
    ]

    func testSelectCN_syncsMirror_andMakesSherpaProxyFirst() {
        NetworkRegion.select(.cn)
        XCTAssertEqual(UserDefaults.standard.string(forKey: NetworkRegion.defaultsKey), "cn")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localMirror"), "cnproxy")
        // The same write reaches the actual sherpa chain:
        XCTAssertEqual(LocalModelDownloader.orderedURLs(fixtureURLs).first?.host, "gh-proxy.com")
    }

    func testSelectIntl_syncsMirror_andKeepsOfficialSourceFirst() {
        NetworkRegion.select(.intl)
        XCTAssertEqual(UserDefaults.standard.string(forKey: NetworkRegion.defaultsKey), "intl")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localMirror"), "hf")
        XCTAssertEqual(LocalModelDownloader.orderedURLs(fixtureURLs).first?.host, "github.com")
    }

    func testLocaleDefault_cnRegionPreselectsCN_othersIntl() {
        XCTAssertEqual(NetworkRegion.localeDefault(Locale(identifier: "zh_CN")), .cn)
        XCTAssertEqual(NetworkRegion.localeDefault(Locale(identifier: "en_US")), .intl)
        XCTAssertEqual(NetworkRegion.localeDefault(Locale(identifier: "ja_JP")), .intl)
    }

    func testUnsetRegion_neverWrites_andOldMirrorChoiceSurvives() {
        // Old user: chose a mirror by hand, never saw the region picker.
        UserDefaults.standard.removeObject(forKey: NetworkRegion.defaultsKey)
        UserDefaults.standard.set("cnproxy", forKey: "localMirror")
        _ = NetworkRegion.current   // reading must not write anything
        XCTAssertNil(UserDefaults.standard.string(forKey: NetworkRegion.defaultsKey))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localMirror"), "cnproxy")
    }

    func testManualMirrorOverride_doesNotFlipRegion() {
        NetworkRegion.select(.intl)
        // User then manually prefers the proxy mirror (e.g. corporate network).
        UserDefaults.standard.set("cnproxy", forKey: "localMirror")
        XCTAssertEqual(NetworkRegion.current, .intl)   // region untouched (one-way sync)
        XCTAssertEqual(LocalModelDownloader.orderedURLs(fixtureURLs).first?.host, "gh-proxy.com")
    }
}
