import AppKit
import XCTest
@testable import ResponsayMac

@MainActor
final class OverlayPanelSizingTests: XCTestCase {

    private func makePanel() -> NSPanel {
        NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
    }

    // MARK: - resolved

    func testResolvedReturnsFallbackWhenMeasurementMissing() {
        let fallback = CGSize(width: 204, height: 80)
        XCTAssertEqual(OverlayPanelSizing.resolved(nil, fallback: fallback), fallback)
        XCTAssertEqual(OverlayPanelSizing.resolved(.zero, fallback: fallback), fallback)
    }

    func testResolvedFallsBackPerAxis() {
        let fallback = CGSize(width: 204, height: 80)
        XCTAssertEqual(
            OverlayPanelSizing.resolved(CGSize(width: 0.5, height: 60), fallback: fallback),
            CGSize(width: 204, height: 60))
        XCTAssertEqual(
            OverlayPanelSizing.resolved(CGSize(width: 300, height: 0), fallback: fallback),
            CGSize(width: 300, height: 80))
    }

    func testResolvedPassesThroughRealMeasurement() {
        let measured = CGSize(width: 312, height: 96)
        XCTAssertEqual(
            OverlayPanelSizing.resolved(measured, fallback: CGSize(width: 204, height: 80)),
            measured)
    }

    // MARK: - pin(contentSize:)

    func testPinSetsAndFreezesContentSize() {
        let panel = makePanel()
        let size = CGSize(width: 200, height: 80)

        OverlayPanelSizing.pin(panel, contentSize: size, label: "test")

        XCTAssertEqual(panel.frame.size, size)
        XCTAssertEqual(panel.contentMinSize, size)
        XCTAssertEqual(panel.contentMaxSize, size)
    }

    func testRepinAtNewSizeTakesEffect() {
        let panel = makePanel()
        OverlayPanelSizing.pin(panel, contentSize: CGSize(width: 200, height: 80), label: "test")

        let grown = CGSize(width: 320, height: 170)
        OverlayPanelSizing.pin(panel, contentSize: grown, label: "test")

        XCTAssertEqual(panel.frame.size, grown)
        XCTAssertEqual(panel.contentMinSize, grown)
        XCTAssertEqual(panel.contentMaxSize, grown)
    }

    func testRepinAtSameSizeKeepsFrameOrigin() {
        let panel = makePanel()
        let size = CGSize(width: 200, height: 80)
        OverlayPanelSizing.pin(panel, contentSize: size, label: "test")
        panel.setFrameOrigin(NSPoint(x: 123, y: 456))

        OverlayPanelSizing.pin(panel, contentSize: size, label: "test")

        XCTAssertEqual(panel.frame.origin, NSPoint(x: 123, y: 456))
        XCTAssertEqual(panel.frame.size, size)
    }

    // MARK: - pin(frame:)

    func testPinFramePlacesAndFreezes() {
        let panel = makePanel()
        let rect = NSRect(x: 40, y: 60, width: 360, height: 120)

        OverlayPanelSizing.pin(panel, frame: rect, label: "test")

        XCTAssertEqual(panel.frame, rect)
        XCTAssertEqual(panel.contentMinSize, rect.size)
        XCTAssertEqual(panel.contentMaxSize, rect.size)
    }

    func testPinFrameGrowingDownwardKeepsTopEdge() {
        let panel = makePanel()
        OverlayPanelSizing.pin(
            panel, frame: NSRect(x: 40, y: 100, width: 360, height: 120), label: "test")

        // Menu expands: same top-left in screen space = lower origin, taller frame.
        OverlayPanelSizing.pin(
            panel, frame: NSRect(x: 40, y: 40, width: 360, height: 180), label: "test")

        XCTAssertEqual(panel.frame, NSRect(x: 40, y: 40, width: 360, height: 180))
        XCTAssertEqual(panel.contentMinSize, CGSize(width: 360, height: 180))
        XCTAssertEqual(panel.contentMaxSize, CGSize(width: 360, height: 180))
    }
}
