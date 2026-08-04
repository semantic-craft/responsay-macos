import XCTest
import SwiftUI
import AppKit
@testable import ResponsayMac

/// Renders every `CapsuleSkin` across every phase to PNGs, so the 录音胶囊外观 axis — which is
/// *entirely* visual — can be reviewed without driving the menu-bar app and its global hotkeys.
///
/// Same hosting approach as `SettingsSnapshotEvidenceTests`: an off-screen `NSWindow` so the
/// SwiftUI lifecycle runs and `onAppear` animations start before capture. Output dir comes from
/// `RESPONSAY_SNAPSHOT_DIR`, falling back to the temp dir.
///
/// The capsule floats over the user's screen, so each sheet draws it on a gradient ground rather
/// than a flat colour: 光之骨架 is mostly glow and translucency, and on a solid backdrop it would
/// look like a grey lozenge — exactly the failure mode this evidence exists to catch.
@MainActor
final class CapsuleSkinSnapshotTests: XCTestCase {

    /// `UnifiedCapsule` resolves `CapsuleSkin.current` from `UserDefaults.standard` at render time
    /// (by design — that is what makes a skin swap re-dress the next capsule), so these tests have
    /// to write the real key. Snapshot it up front and restore it verbatim afterwards.
    private var capsuleSkinBackup: Any?

    override func setUp() {
        super.setUp()
        capsuleSkinBackup = UserDefaults.standard.object(forKey: CapsuleSkin.defaultsKey)
    }

    override func tearDown() {
        if let capsuleSkinBackup {
            UserDefaults.standard.set(capsuleSkinBackup, forKey: CapsuleSkin.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CapsuleSkin.defaultsKey)
        }
        super.tearDown()
    }

    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["RESPONSAY_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - Sheets

    func testCapsuleSkinSheets() throws {
        for skin in CapsuleSkin.allCases {
            UserDefaults.standard.set(skin.rawValue, forKey: CapsuleSkin.defaultsKey)
            for dark in [false, true] {
                let name = "capsule-\(skin.rawValue)-\(dark ? "dark" : "light").png"
                let url = try capture(sheet(for: skin), size: NSSize(width: 760, height: 470),
                                      dark: dark, named: name)
                print("📸 \(url.path)")
            }
        }
    }

    /// The 外观主题 pane, where the axis is actually chosen — the swatches are hand-drawn
    /// miniatures rather than live capsules, so they need their own look.
    func testAppearancePaneSheet() throws {
        UserDefaults.standard.set(CapsuleSkin.psychoFrame.rawValue, forKey: CapsuleSkin.defaultsKey)
        let url = try capture(
            AppearanceScreen(interfaceLanguage: .constant("system"))
                .environment(AppearanceStore.shared),
            size: NSSize(width: 720, height: 940), dark: false, named: "appearance-pane.png")
        print("📸 \(url.path)")
    }

    /// One skin, every phase, plus the ask-mode row that proves 光之骨架 flips hue on mode.
    private func sheet(for skin: CapsuleSkin) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("\(skin.displayName) · \(skin.tagline)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 26) {
                labelled("待机")   { UnifiedCapsule(mode: .voice, phase: .idle) }
                labelled("录音中") { UnifiedCapsule(mode: .voice, phase: .listening, level: 0.62) }
            }
            HStack(alignment: .center, spacing: 26) {
                labelled("整理中") { UnifiedCapsule(mode: .voice, phase: .transcribing) }
                labelled("出错")   { UnifiedCapsule(mode: .voice, phase: .error) }
            }
            labelled("结果") {
                UnifiedCapsule(mode: .voice, phase: .result, liveText: "改到周四上午十点对我最合适")
            }
            labelled("提问 · 录音中") {
                UnifiedCapsule(mode: .ask, phase: .listening, level: 0.55,
                               askLabelText: "任意提问 · 再按 Fn 结束")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(desktop)
    }

    private func labelled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
            content()
        }
    }

    /// Stand-in for the user's desktop: the capsule is never seen on a flat colour.
    private var desktop: some View {
        LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Capture

    private func capture<V: View>(_ view: V, size: NSSize, dark: Bool, named name: String) throws -> URL {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        // Off the visible screen so a real console session is never interrupted, but ordered-in
        // so the window server backs it and SwiftUI lays it out.
        let window = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: size.width, height: size.height),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        window.displayIfNeeded()

        // Let onAppear fire and the repeating animations reach a non-zero pose.
        pumpRunLoop(seconds: 1.2)
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
}
