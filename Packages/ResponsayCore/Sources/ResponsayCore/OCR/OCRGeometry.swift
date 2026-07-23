import CoreGraphics
import Foundation

// MARK: - 070 Snap & Translate · OCR coordinate helper
//
// Apple Vision returns bounding boxes in a normalized, bottom-left origin space (values 0–1).
// Image / screen space is top-left origin in pixels. This pure helper does the conversion in
// one place so every provider (and the 073 result window) shares one Y-flip and one scale.

public enum OCRGeometry {
    /// Vision normalized box (bottom-left origin, 0–1) → pixel box (top-left origin, image space).
    ///
    /// The Y flip: a pixel row's top is `(1 − normalized.maxY) × imageHeight`, because Vision
    /// measures from the bottom. Width/height scale straight by the image dimensions.
    public static func pixelRect(fromNormalized norm: CGRect, imageSize: CGSize) -> CGRect {
        let x = norm.minX * imageSize.width
        let width = norm.width * imageSize.width
        let height = norm.height * imageSize.height
        let y = (1 - norm.maxY) * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
