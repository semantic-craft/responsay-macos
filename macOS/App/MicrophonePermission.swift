import AppKit
import AVFAudio
import AVFoundation
import OSLog
import ResponsayCore

enum MicrophonePermission {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "permissions")

    static var isGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    @MainActor
    static func promptIfNeeded() -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            log.error("Microphone permission denied; opening System Settings")
            openSystemSettings()
            return false
        case .undetermined:
            log.warning("Microphone permission undetermined; showing primer")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = String(localized: "\(AppBrand.displayName) 需要麦克风权限")
            alert.informativeText = String(localized: "语音输入要先录到你的声音,然后才会发送给本地后端做中文识别。点击”请求权限”后,请在 macOS 弹窗里选择允许。")
            alert.alertStyle = .informational
            alert.addButton(withTitle: String(localized: "请求权限"))
            alert.addButton(withTitle: String(localized: "取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return false }

            let logger = log
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable granted in
                logger.info("Microphone media-capture primer completed; granted \(granted, privacy: .public)")
            }
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                logger.info("Microphone permission primer completed; granted \(granted, privacy: .public)")
            }
            return false
        @unknown default:
            log.warning("Unknown microphone permission status; continuing")
            return true
        }
    }

    /// Throwing gate shared by cloud ASR capture services. Returns on granted/unknown; on
    /// `undetermined` it kicks off the system request and throws a "press again"
    /// message; on `denied` it throws an "open Settings" message. `feature` is
    /// used only in the log line.
    static func ensure(feature: String) throws {
        let logger = log
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .undetermined:
            logger.warning("Microphone permission undetermined for \(feature, privacy: .public); requesting access")
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                logger.info("Microphone permission request completed for \(feature, privacy: .public); granted \(granted, privacy: .public)")
            }
            throw CoachAPIError.message("正在请求麦克风授权，授权后请再按一次。")
        case .denied:
            logger.error("Microphone permission denied for \(feature, privacy: .public)")
            throw CoachAPIError.message("麦克风未授权。请到 系统设置 › 隐私与安全性 › 麦克风 开启。")
        @unknown default:
            return
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
