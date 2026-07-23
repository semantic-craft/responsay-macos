import CoreGraphics

enum PanelPlacement {
    static let defaultEdgeMargin: CGFloat = 40

    static func bottomCentered(
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = defaultEdgeMargin
    ) -> CGPoint {
        CGPoint(
            x: centeredOrigin(containerMin: visibleFrame.minX, containerMax: visibleFrame.maxX, size: panelSize.width),
            y: clampedOrigin(
                preferred: visibleFrame.minY + margin,
                min: visibleFrame.minY,
                max: visibleFrame.maxY - panelSize.height
            )
        )
    }

    static func centered(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: centeredOrigin(containerMin: visibleFrame.minX, containerMax: visibleFrame.maxX, size: panelSize.width),
            y: centeredOrigin(containerMin: visibleFrame.minY, containerMax: visibleFrame.maxY, size: panelSize.height)
        )
    }

    private static func centeredOrigin(containerMin: CGFloat, containerMax: CGFloat, size: CGFloat) -> CGFloat {
        clampedOrigin(
            preferred: (containerMin + containerMax - size) / 2,
            min: containerMin,
            max: containerMax - size
        )
    }

    private static func clampedOrigin(preferred: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        guard max >= min else { return min }
        return Swift.max(min, Swift.min(preferred, max))
    }
}
