import Testing
import Foundation

@Suite("Sparkle integration — plist keys")
struct SparkleIntegrationTests {

    @Test("SUFeedURL points to production appcast")
    func feedURLConfigured() {
        let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(url == "https://raw.githubusercontent.com/semantic-craft/responsay-macos/main/appcast.xml")
    }

    @Test("SUPublicEDKey is present and non-empty")
    func publicKeyConfigured() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        #expect(key != nil)
        #expect(key?.isEmpty == false)
    }
}
