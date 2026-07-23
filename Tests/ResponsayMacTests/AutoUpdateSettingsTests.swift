import Testing
import Foundation
@testable import ResponsayMac

@Suite("Settings update UI contract")
@MainActor
struct AutoUpdateSettingsTests {

    @Test("AutoUpdateService toggle can be flipped")
    func toggleAutoCheck() {
        let service = AutoUpdateService()
        service.automaticallyChecksForUpdates = false
        #expect(service.automaticallyChecksForUpdates == false)
        service.automaticallyChecksForUpdates = true
        #expect(service.automaticallyChecksForUpdates == true)
    }

    @Test("Bundle exposes MARKETING_VERSION")
    func marketingVersionExists() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version != nil)
        #expect(version?.isEmpty == false)
    }
}
