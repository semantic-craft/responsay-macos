import AppKit
import ResponsayCore

/// Everything the old SwiftUI `ResponsayMacApp.init` constructed, now owned by a plain object
/// the AppKit entry point (`main.swift`) keeps alive (#578). Behaviour is a straight port:
/// pure object construction here, side effects deferred to `applicationDidFinishLaunching`
/// via `startAction` (337), DEBUG smoke wiring unchanged.
///
/// 332: no launch-time BYOK header install. macOS reaches every provider app-direct
/// (ADR-0029); keys reach providers via ProviderConfigDispatcher.resolve() /
/// ProviderCredentialStore only.
@MainActor
final class AppBootstrap {
    let controller: CaptureController
    let startAction: () -> Void
    private let updateService = AutoUpdateService.shared
    #if DEBUG
    // Smoke automation hook (URL scheme + Darwin notifications). DEBUG-only: it can trigger
    // capture/insertion/context+selection probes, so it must never ship in a Release build.
    private var smokeURLHandler: SmokeURLHandler?
    #endif

    init() {
        let controller = CaptureController()
        self.controller = controller

        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.startAction = {}
            return
        }
        #endif

        #if DEBUG
        let designReviewFixture = ProcessInfo.processInfo.arguments.contains("--design-review-fixture")
        #else
        let designReviewFixture = false
        #endif
        let showOnboarding = ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        let firstRunOnboarding = !UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey)
        // 337: defer the Sparkle updater start to applicationDidFinishLaunching alongside
        // controller.start — launch carries no side effects until the delegate fires.
        let updater = updateService
        self.startAction = {
            controller.start(promptForAccessibility: !(designReviewFixture || showOnboarding || firstRunOnboarding))
            try? updater.startUpdater()
        }

        #if DEBUG
        if designReviewFixture {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                controller.showDesignReviewFixture()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--snap-ocr-fixture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                controller.showSnapOCRFixture()
            }
        }
        let smokeURLHandler = SmokeURLHandler(controller: controller)
        self.smokeURLHandler = smokeURLHandler
        smokeURLHandler.startDarwinNotifications()
        NSAppleEventManager.shared().setEventHandler(
            smokeURLHandler,
            andSelector: #selector(SmokeURLHandler.handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
        #endif
    }
}
