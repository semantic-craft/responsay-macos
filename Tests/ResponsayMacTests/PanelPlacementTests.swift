import CoreGraphics
import XCTest
@testable import ResponsayMac

final class PanelPlacementTests: XCTestCase {

    func testBottomCapsuleStaysInsideMacBookVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 74, width: 3024, height: 1810)
        let panelSize = CGSize(width: 360, height: 72)

        let origin = PanelPlacement.bottomCentered(panelSize: panelSize, visibleFrame: visibleFrame)

        XCTAssertEqual(origin.x, 1332)
        XCTAssertEqual(origin.y, 114)
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, visibleFrame.maxY)
    }

    func testBottomCapsuleClampsToVisibleFrameOnShortDisplays() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 320, height: 100)
        let panelSize = CGSize(width: 280, height: 80)

        let origin = PanelPlacement.bottomCentered(panelSize: panelSize, visibleFrame: visibleFrame)

        XCTAssertEqual(origin, CGPoint(x: 120, y: 70))
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, visibleFrame.maxY)
    }

    func testCenteredPanelClampsHorizontallyWhenDisplayIsNarrow() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 420, height: 800)
        let panelSize = CGSize(width: 508, height: 596)

        let origin = PanelPlacement.centered(panelSize: panelSize, visibleFrame: visibleFrame)

        XCTAssertEqual(origin.x, visibleFrame.minX)
        XCTAssertEqual(origin.y, 142)
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, visibleFrame.maxY)
    }
}
