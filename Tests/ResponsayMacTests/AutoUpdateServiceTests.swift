import Testing
@testable import ResponsayMac

@Suite("AutoUpdateService")
@MainActor
struct AutoUpdateServiceTests {

    @Test("initializes without crashing")
    func initDoesNotCrash() {
        let service = AutoUpdateService()
        #expect(service != nil)
    }

    @Test("automaticallyChecksForUpdates defaults to true")
    func autoCheckDefaultsTrue() {
        let service = AutoUpdateService()
        #expect(service.automaticallyChecksForUpdates == true)
    }

    @Test("canCheckForUpdates is initially false before updater starts")
    func canCheckInitiallyFalse() {
        let service = AutoUpdateService()
        #expect(service.canCheckForUpdates == false)
    }
}
