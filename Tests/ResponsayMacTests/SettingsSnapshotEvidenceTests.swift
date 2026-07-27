import XCTest
import SwiftUI
import AppKit
import ResponsayCore
@testable import ResponsayMac

/// Renders the redesigned settings surface (5 domain groups + per-capability
/// engine cards) to PNGs so the openless-style model configuration — provider
/// picker, customizable Base URL / Model, Fetch-models / Validate — can be
/// reviewed visually without driving the GUI.
///
/// Each view is hosted in an off-screen `NSWindow` (exactly how the real app
/// hosts `SettingsView()` via `NSHostingController`) so the SwiftUI lifecycle
/// runs and `onAppear` loads catalog defaults before capture. Output dir comes
/// from `RESPONSAY_SNAPSHOT_DIR`, falling back to the temp dir.
@MainActor
final class SettingsSnapshotEvidenceTests: XCTestCase {

    /// The rendered cards persist to `UserDefaults.standard` (the real app
    /// domain, since `CapabilityCardView` reads it directly), so snapshot the
    /// `byok.*` routing keys up front and restore them verbatim afterwards —
    /// the suite must leave the developer's real BYOK selections untouched.
    private var byokBackup: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        byokBackup = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("byok.") }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("byok.") {
            d.removeObject(forKey: key)
        }
        for (k, v) in byokBackup { d.set(v, forKey: k) }
        super.tearDown()
    }

    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["RESPONSAY_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func clearBYOK(_ capability: String) {
        let d = UserDefaults.standard
        for suffix in ["provider", "region", "plan", "model", "baseURL"] {
            d.removeObject(forKey: "byok.\(capability).\(suffix)")
        }
    }

    private func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    @discardableResult
    private func capture<V: View>(_ view: V, size: NSSize, named name: String) throws -> URL {
        let host = NSHostingView(rootView:
            view
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(AppearanceStore.shared)   // matches production hosting
        )
        host.frame = NSRect(origin: .zero, size: size)

        // Off the visible screen so a real console session is never interrupted,
        // but ordered-in so the window server backs and lays it out.
        let window = NSWindow(
            contentRect: NSRect(x: -8000, y: -8000, width: size.width, height: size.height),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        window.displayIfNeeded()

        // Let onAppear / async catalog loads + layout settle.
        pumpRunLoop(seconds: 1.4)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw XCTSkip("no bitmap rep for \(name)")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("no png encoding for \(name)")
        }
        let url = outputDir.appendingPathComponent(name)
        try png.write(to: url)
        window.orderOut(nil)
        XCTAssertGreaterThan(png.count, 3000, "snapshot \(name) looks blank (\(png.count) bytes)")
        return url
    }

    /// Window-server composite capture of the app's OWN window — renders the
    /// `NavigationSplitView` sidebar that AppKit `cacheDisplay` and SwiftUI
    /// `ImageRenderer` both miss offscreen. Capturing one's own window needs no
    /// Screen Recording grant. Shown on-screen ~1.4s, then closed.
    @discardableResult
    private func captureWindow<V: View>(_ view: V, size: NSSize, named name: String) throws -> URL {
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(AppearanceStore.shared))   // matches production hosting
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 120, width: size.width, height: size.height),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.title = "Responsay Settings"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        pumpRunLoop(seconds: 1.4)

        let wid = CGWindowID(window.windowNumber)
        let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, wid,
                                         [.boundsIgnoreFraming, .bestResolution])
        window.orderOut(nil)
        guard let cg else { throw XCTSkip("no window image for \(name)") }
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        guard let png else { throw XCTSkip("no png for \(name)") }
        let url = outputDir.appendingPathComponent(name)
        try png.write(to: url)
        XCTAssertGreaterThan(png.count, 5000, "snapshot \(name) looks blank (\(png.count) bytes)")
        return url
    }

    /// Full redesigned settings window: 输入 / 引擎 / 法律 / 英语 / 系统 sidebar groups.
    func testSettingsOverviewSnapshot() throws {
        let url = try captureWindow(SettingsView(), size: NSSize(width: 1040, height: 720),
                                    named: "settings-overview.png")
        print("SNAPSHOT settings-overview -> \(url.path)")
    }

    /// LLM engine card in its out-of-box default: 通义千问 · 阿里云, Base URL +
    /// Model prefilled from the catalog, Validate / Fetch models.
    func testLLMCardDefaultSnapshot() throws {
        clearBYOK("llm")
        let url = try capture(CapabilityCardView(capability: .llm),
                              size: NSSize(width: 660, height: 560),
                              named: "llm-card-default-qwen.png")
        print("SNAPSHOT llm-card-default -> \(url.path)")
    }

    /// ASR + TTS engine cards (the other two per-capability panes).
    func testASRandTTSCardSnapshots() throws {
        clearBYOK("asr")
        let asr = try capture(CapabilityCardView(capability: .asr),
                              size: NSSize(width: 660, height: 520),
                              named: "asr-card-default.png")
        print("SNAPSHOT asr-card -> \(asr.path)")
        clearBYOK("tts")
        let tts = try capture(CapabilityCardView(capability: .tts),
                              size: NSSize(width: 660, height: 520),
                              named: "tts-card-default.png")
        print("SNAPSHOT tts-card -> \(tts.path)")
    }

}
