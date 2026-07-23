import CoreGraphics
import Foundation
import ImageIO
import OSLog
import ResponsayCore

// MARK: - 070 Snap & Translate · screen-region capture
//
// Gets a CGImage from a user-selected screen region. A seam so the capture *mechanism* can change
// without touching callers: today the system `screencapture -i` selector (ADR-0005 amendment),
// later a hand-drawn ScreenCaptureKit overlay if we ever need in-app control of the selection UI.

protocol ScreenRegionCapturer: Sendable {
    /// Present an interactive region selector. Returns the captured image, or `nil` if the user
    /// cancelled (Esc) or capture failed — callers treat `nil` as "do nothing", not an error.
    func captureRegion() async -> CGImage?
}

/// Wraps the system `screencapture -i` interactive selector (the ⌘⇧4 crosshair). Chosen over a
/// hand-drawn SCK overlay (see ADR-0005 amendment): native multi-display / Retina / HDR selection
/// for free, Esc-to-cancel, most reliable, ~40 lines. The system binary captures the pixels; we
/// decode the temp PNG via ImageIO (no AppKit). `-x` mutes the shutter sound.
struct SystemScreenRegionCapturer: ScreenRegionCapturer {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "ocr-capture")

    func captureRegion() async -> CGImage? {
        // `screencapture` blocks until the user finishes/cancels the selection; run it off the
        // calling actor so a Snap & Translate triggered from the main actor never blocks the UI.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runInteractiveCapture())
            }
        }
    }

    private static func runInteractiveCapture() -> CGImage? {
        let path = NSTemporaryDirectory() + "responsay-ocr-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", path]   // -i interactive region select, -x silent
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("screencapture launch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        defer { try? FileManager.default.removeItem(atPath: path) }
        // No file / empty file = the user pressed Esc (cancelled the selection). That is a normal
        // outcome, not a failure — return nil and let the caller stay idle.
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return image
    }
}
