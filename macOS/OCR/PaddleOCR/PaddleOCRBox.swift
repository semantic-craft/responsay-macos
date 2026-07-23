import CoreGraphics
import Foundation

struct PaddleOCRBox: Equatable, Sendable {
    var rect: CGRect
    var confidence: Float

    static func readingOrder(_ boxes: [PaddleOCRBox]) -> [PaddleOCRBox] {
        boxes.sorted {
            if abs($0.rect.minY - $1.rect.minY) < 10 {
                return $0.rect.minX < $1.rect.minX
            }
            return $0.rect.minY < $1.rect.minY
        }
    }

    static func mergeIntoLines(_ boxes: [PaddleOCRBox]) -> [PaddleOCRBox] {
        var lines: [PaddleOCRBox] = []
        for box in readingOrder(boxes) {
            if let idx = lines.firstIndex(where: { canMerge($0.rect, box.rect) }) {
                let current = lines[idx]
                let merged = current.rect.union(box.rect)
                let confidence = max(current.confidence, box.confidence)
                lines[idx] = PaddleOCRBox(rect: merged, confidence: confidence)
            } else {
                lines.append(box)
            }
        }
        return readingOrder(lines)
    }

    private static func canMerge(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let minHeight = max(1, min(a.height, b.height))
        let verticalAligned = overlap / minHeight > 0.45
        let gap = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
        return verticalAligned && gap < max(24, minHeight * 1.8)
    }
}
