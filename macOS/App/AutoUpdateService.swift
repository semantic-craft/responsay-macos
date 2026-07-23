import Foundation
import Sparkle

@MainActor
@Observable
final class AutoUpdateService {
    /// Process-wide single instance. Sparkle's updater is process-global; a second
    /// instance never gets `startUpdater()` called, so its `canCheckForUpdates`
    /// stays false forever (that was the "检查更新" greyed-out bug — the settings
    /// pane bound to a second, never-started instance).
    static let shared = AutoUpdateService()

    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func startUpdater() throws {
        try updaterController.updater.start()
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}
