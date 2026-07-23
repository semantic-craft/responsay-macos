import AppKit
import OSLog
import ResponsayCore

/// Local automation hook for smoke tests. It routes a custom URL scheme to the
/// same controller actions as menu items and hotkeys, so tests can trigger the
/// real microphone/backend flow without depending on synthetic global key events.
@MainActor
final class SmokeURLHandler: NSObject {
    private static let triggerNotification = "com.semanticcraft.responsay.smoke.trigger"
    private static let rawTriggerNotification = "com.semanticcraft.responsay.smoke.trigger-raw"
    private static let polishedTriggerNotification = "com.semanticcraft.responsay.smoke.trigger-polished"
    private static let expressTriggerNotification = "com.semanticcraft.responsay.smoke.trigger-express"
    private static let rewriteNotification = "com.semanticcraft.responsay.smoke.rewrite-selection"
    private static let contextProbeNotification = "com.semanticcraft.responsay.smoke.context-probe"
    private static let confirmInsertNotification = "com.semanticcraft.responsay.smoke.confirm-insert"
    private static let insertProbeNotification = "com.semanticcraft.responsay.smoke.insert-probe"
    private static let selectionProbeNotification = "com.semanticcraft.responsay.smoke.selection-probe"
    private static let autoLearnProbeNotification = "com.semanticcraft.responsay.smoke.auto-learn-probe"
    private static let fixtureCapsuleListeningNotification = "com.semanticcraft.responsay.smoke.fixture-capsule-listening"
    private static let fixtureCapsuleFinalizingNotification = "com.semanticcraft.responsay.smoke.fixture-capsule-finalizing"
    private static let fixtureReviewNotification = "com.semanticcraft.responsay.smoke.fixture-review"
    private static let fixtureClearNotification = "com.semanticcraft.responsay.smoke.fixture-clear"
    private static let snapOCRNotification = "com.semanticcraft.responsay.smoke.snap-ocr"
    private static let snapCopyOCRNotification = "com.semanticcraft.responsay.smoke.snap-copy-ocr"

    private weak var controller: CaptureController?
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "smoke-url")

    init(controller: CaptureController) {
        self.controller = controller
        super.init()
    }

    func startDarwinNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for notification in [
            Self.triggerNotification,
            Self.rawTriggerNotification,
            Self.polishedTriggerNotification,
            Self.expressTriggerNotification,
            Self.rewriteNotification,
            Self.contextProbeNotification,
            Self.confirmInsertNotification,
            Self.insertProbeNotification,
            Self.selectionProbeNotification,
            Self.autoLearnProbeNotification,
            Self.fixtureCapsuleListeningNotification,
            Self.fixtureCapsuleFinalizingNotification,
            Self.fixtureReviewNotification,
            Self.fixtureClearNotification,
            Self.snapOCRNotification,
            Self.snapCopyOCRNotification
        ] {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let handler = Unmanaged<SmokeURLHandler>.fromOpaque(observer).takeUnretainedValue()
                    let rawName = name.rawValue as String
                    Task { @MainActor in handler.handleDarwinNotification(rawName) }
                },
                notification as CFString,
                nil,
                .deliverImmediately)
        }
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        handle(url)
    }

    private func handle(_ url: URL) {
        log.info("Smoke URL received: \(url.absoluteString, privacy: .public)")
        applyQuerySettings(from: url)
        switch url.host {
        case "trigger":
            controller?.trigger()
        case "trigger-raw":
            controller?.triggerRaw()
        case "trigger-polished":
            controller?.triggerPolished()
        case "trigger-express":
            controller?.triggerExpressInEnglish()
        case "rewrite-selection":
            controller?.rewriteSelection()
        case "context-probe":
            controller?.probeContext()
        case "insert-probe":
            controller?.probeInsert()
        case "selection-probe":
            controller?.probeSelection()
        case "confirm-insert":
            controller?.confirmInsert()
        case "open-main":
            // Design-review/screenshot hook (311): open the main window on a
            // given sidebar section, e.g. responsay://open-main?screen=polish
            MainWindowController.shared.show()
            let screen = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "screen" })?.value ?? "overview"
            NotificationCenter.default.post(name: .init("OpenMainSection"), object: screen)
        #if DEBUG
        case "fixture-capsule-listening":
            controller?.showCapsuleListeningFixture()
        case "fixture-capsule-finalizing":
            controller?.showCapsuleFinalizingFixture()
        case "fixture-review":
            controller?.showDesignReviewFixture()
        case "fixture-clear":
            controller?.clearDesignFixture()
        case "auto-learn-probe":
            controller?.probeAutoLearnSeed()
        case "shortcut-bindings":
            controller?.debugLogShortcutBindings()
        case "snap-ocr":
            controller?.snapOCR()
        case "snap-copy-ocr":
            controller?.snapTextOCR()
        case "snap-ocr-fixture":
            controller?.showSnapOCRFixture()
        case "simulate-normal":
            controller?.debugSimulateNormalHotkey(
                actionRaw: queryValue("action", in: url) ?? "raw",
                slotIndex: Int(queryValue("slot", in: url) ?? "0") ?? 0,
                phaseRaw: queryValue("phase", in: url) ?? "down"
            )
        case "simulate-fn":
            controller?.debugSimulateFnHotkey(
                chordID: queryValue("chord", in: url) ?? "fn",
                phaseRaw: queryValue("phase", in: url) ?? "down"
            )
        #endif
        default:
            break
        }
    }

    private func applyQuerySettings(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        for item in components.queryItems ?? [] {
            switch item.name {
            case "asr":
                if let value = item.value {
                    UserDefaults.standard.set(value, forKey: ASREngine.defaultsKey)
                }
            case "region":
                if let value = item.value {
                    UserDefaults.standard.set(value, forKey: RealtimeQwenSettings.regionKey)
                }
            case "hold":
                if let value = item.value {
                    UserDefaults.standard.set(value == "1" || value == "true", forKey: "triggerMode")
                }
            case "locale":
                if let value = item.value {
                    UserDefaults.standard.set(value, forKey: "defaultLocale")
                }
            default:
                break
            }
        }
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?.first { $0.name == name }?.value
    }

    private func handleDarwinNotification(_ name: String) {
        log.info("Smoke notification received: \(name, privacy: .public)")
        switch name {
        case Self.triggerNotification:
            controller?.trigger()
        case Self.rawTriggerNotification:
            controller?.triggerRaw()
        case Self.polishedTriggerNotification:
            controller?.triggerPolished()
        case Self.expressTriggerNotification:
            controller?.triggerExpressInEnglish()
        case Self.rewriteNotification:
            controller?.rewriteSelection()
        case Self.contextProbeNotification:
            controller?.probeContext()
        case Self.insertProbeNotification:
            controller?.probeInsert()
        case Self.selectionProbeNotification:
            controller?.probeSelection()
        case Self.confirmInsertNotification:
            controller?.confirmInsert()
        #if DEBUG
        case Self.autoLearnProbeNotification:
            controller?.probeAutoLearnSeed()
        case Self.fixtureCapsuleListeningNotification:
            controller?.showCapsuleListeningFixture()
        case Self.fixtureCapsuleFinalizingNotification:
            controller?.showCapsuleFinalizingFixture()
        case Self.fixtureReviewNotification:
            controller?.showDesignReviewFixture()
        case Self.fixtureClearNotification:
            controller?.clearDesignFixture()
        case Self.snapOCRNotification:
            controller?.snapOCR()
        case Self.snapCopyOCRNotification:
            controller?.snapTextOCR()
        #endif
        default:
            break
        }
    }
}
