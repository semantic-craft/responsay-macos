import AppKit
import OSLog
import ResponsayCore

@MainActor
final class CaptureSnapOCRController {
    private let vm: QuickCaptureViewModel
    private let log: Logger
    private var snapInFlight = false

    init(vm: QuickCaptureViewModel, log: Logger) {
        self.vm = vm
        self.log = log
    }

    func snapOCR() {
        guard prepareForSnap(label: "Snap & Translate", retry: { [weak self] in self?.snapOCR() }) else {
            return
        }
        log.info("Snap & Translate (OCR) requested")

        let permissionWasMissing = !ScreenRecordingPermission.isAuthorized
        guard requestScreenRecordingIfNeeded() else { return }
        let router = RoutedOCRProvider()
        let runner = SnapOCRRunner(provider: router.resolve())
        snapInFlight = true
        Task {
            defer { snapInFlight = false }
            var capturedImage: CGImage?
            let outcome = await runner.run(
                onCaptured: { capturedImage = $0 },
                onRecognizing: { vm.beginSnapRecognizing() })
            switch outcome {
            case .cancelled:
                vm.endSnapRecognizing()
                // No capture while the permission was missing at start → if the user
                // just granted it, macOS only applies it after a relaunch. Offer one.
                if permissionWasMissing && !ScreenRecordingPermission.isAuthorized {
                    AppRelaunch.promptScreenRecordingRelaunch()
                } else {
                    log.debug("Snap & Translate cancelled or no capture")
                    showSnapAlert(title: "截图没有完成", message: "如果你已经框选了区域，说明系统截图没有返回图片；请检查屏幕录制权限后再试。")
                }
            case let .recognized(result):
                log.info("OCR recognized \(result.text.count, privacy: .public) chars")
                vm.endSnapRecognizing()
                guard isUsefulOCRText(result.text) else {
                    vm.fail("只识别到很少文字，请框选更完整的文本区域。")
                    showSnapAlert(title: "识别到的文字太少", message: "Responsay 只读到：\(result.text)")
                    return
                }
                // 原文 → 译文 面板（双栏 + 切换 AI 服务对比 + 复制译文 + 智能分段），取代旧的
                // 「地道说法」改写卡。截图翻译不再走 vm.processText(.snapTranslatePreview)。
                SnapTranslatePanel.shared.show(result: result, image: capturedImage)
            case .empty:
                if permissionWasMissing && !ScreenRecordingPermission.isAuthorized {
                    AppRelaunch.promptScreenRecordingRelaunch()
                } else {
                    vm.fail("没有识别到文字。")
                    showSnapAlert(title: "没有识别到文字", message: "请框选清晰的文本区域，或在图片识别设置里切换 OCR 引擎。")
                }
            case let .failed(message):
                log.error("OCR failed: \(message, privacy: .public)")
                vm.fail(message)
                showSnapAlert(title: "截图翻译失败", message: message)
            }
        }
    }

    /// 截图取字（原「截图复制」）：框选 → 识别 → 弹出可编辑结果面板（复制 / 智能分段 / 切换引擎再识别）。
    /// 不再静默写剪贴板——结果进面板，由用户在面板里复制。
    func snapTextOCR() {
        guard prepareForSnap(label: "Snap OCR", retry: { [weak self] in self?.snapTextOCR() }) else {
            return
        }
        log.info("Snap OCR requested")

        let permissionWasMissing = !ScreenRecordingPermission.isAuthorized
        guard requestScreenRecordingIfNeeded() else { return }
        let router = RoutedOCRProvider()
        let runner = SnapOCRRunner(provider: router.resolve())
        snapInFlight = true
        Task {
            defer { snapInFlight = false }
            var capturedImage: CGImage?
            let outcome = await runner.run(
                onCaptured: { capturedImage = $0 },
                onRecognizing: { vm.beginSnapRecognizing() })
            switch outcome {
            case .cancelled:
                vm.endSnapRecognizing()
                if permissionWasMissing && !ScreenRecordingPermission.isAuthorized {
                    AppRelaunch.promptScreenRecordingRelaunch()
                } else {
                    log.debug("Snap OCR cancelled or no capture")
                    showSnapAlert(title: "截图没有完成", message: "如果你已经框选了区域，说明系统截图没有返回图片；请检查屏幕录制权限后再试。")
                }
            case let .recognized(result):
                log.info("OCR recognized \(result.text.count, privacy: .public) chars")
                vm.endSnapRecognizing()
                // 截图复制到剪贴板: skip the editable panel, write straight to the pasteboard
                // (the classic 截图复制 behavior, opt-in via 图片识别 设置).
                if SnapOCRCopySettings.copyToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    log.info("Snap OCR copied to clipboard (\(result.text.count, privacy: .public) chars)")
                    return
                }
                guard let image = capturedImage else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    return
                }
                SnapOCRPanel.shared.show(result: result, image: image)
            case .empty:
                if permissionWasMissing && !ScreenRecordingPermission.isAuthorized {
                    AppRelaunch.promptScreenRecordingRelaunch()
                } else {
                    vm.fail("没有识别到文字。")
                    showSnapAlert(title: "没有识别到文字", message: "请框选清晰的文本区域，或在图片识别设置里切换 OCR 引擎。")
                }
            case let .failed(message):
                log.error("OCR failed: \(message, privacy: .public)")
                vm.fail(message)
                showSnapAlert(title: "截图取字失败", message: message)
            }
        }
    }

    /// 截图复制：框选屏幕区域 → 把图片本身写入剪贴板（不取字、不翻译、不弹面板）。
    /// 复用 070 的 `SystemScreenRegionCapturer`；`nil` = 用户按 Esc 取消或截图失败。
    func snapImageCopy() {
        guard prepareForSnap(label: "Snap Copy", retry: { [weak self] in self?.snapImageCopy() }) else {
            return
        }
        log.info("Snap Copy requested")

        let permissionWasMissing = !ScreenRecordingPermission.isAuthorized
        guard requestScreenRecordingIfNeeded() else { return }
        snapInFlight = true
        Task {
            defer { snapInFlight = false }
            guard let image = await SystemScreenRegionCapturer().captureRegion() else {
                // No capture: Esc-cancel, or a freshly granted permission macOS only applies
                // after a relaunch — offer one, matching snapOCR / snapTextOCR.
                if permissionWasMissing && !ScreenRecordingPermission.isAuthorized {
                    AppRelaunch.promptScreenRecordingRelaunch()
                } else {
                    log.debug("Snap Copy cancelled or no capture")
                }
                return
            }
            ClipboardImageWriter.write(image)
            log.info("Snap Copy wrote image to clipboard")
            if SnapCopySoundSettings.enabled {
                InteractionSoundPlayer.shared.playSnapCopyDone()
            }
        }
    }

    private func isUsefulOCRText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private func prepareForSnap(label: String, retry: @MainActor @escaping () -> Void) -> Bool {
        guard !snapInFlight else {
            log.debug("\(label, privacy: .public) ignored: OCR is already in flight")
            return false
        }

        switch vm.phase {
        case .listening:
            log.warning("\(label, privacy: .public) requested while listening; cancelling capture before retry")
            Task { @MainActor in
                await vm.cancelCapture()
                retry()
            }
            return false
        case .thinking:
            log.warning("\(label, privacy: .public) requested while another transform is running")
            showBusyAlert()
            return false
        case .idle, .review, .error, .copied:
            return true
        }
    }

    private func showBusyAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Responsay 正在处理上一条内容")
        alert.informativeText = String(localized: "处理完成后再试一次截图翻译。")
        alert.addButton(withTitle: String(localized: "好"))
        alert.runModal()
    }

    private func showSnapAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "好"))
        alert.runModal()
    }

    private func requestScreenRecordingIfNeeded() -> Bool {
        guard !ScreenRecordingPermission.isAuthorized else { return true }
        guard ScreenRecordingPermission.request() || ScreenRecordingPermission.isAuthorized else {
            AppRelaunch.promptScreenRecordingRelaunch()
            return false
        }
        return true
    }
}
