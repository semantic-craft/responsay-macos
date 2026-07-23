import CoreGraphics
import Foundation

struct PaddleOCRDetector {
    private let session: PaddleORTSession
    private let threshold: Float = 0.2
    private let boxThreshold: Float = 0.45

    init(model: PaddleOCRModel) throws {
        session = try PaddleORTSession(modelPath: model.detModel.path, threadCount: 4)
    }

    func detect(_ image: CGImage) throws -> [PaddleOCRBox] {
        let (w, h) = Self.resizedSize(width: image.width, height: image.height)
        let input = try PaddleOCRImage(cgImage: image, width: w, height: h)
        let tensor = try session.run(
            withFloat: input.detectionTensor(),
            shape: [NSNumber(value: 1), NSNumber(value: 3), NSNumber(value: h), NSNumber(value: w)])
        let floats = Self.floats(from: tensor.floatData)
        let shape = tensor.shape.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        let mapH = shape[shape.count - 2]
        let mapW = shape[shape.count - 1]
        guard mapH > 0, mapW > 0, floats.count >= mapH * mapW else { return [] }

        let boxes = components(
            probabilities: floats,
            width: mapW,
            height: mapH,
            originalWidth: image.width,
            originalHeight: image.height)
        return PaddleOCRBox.mergeIntoLines(boxes)
    }

    private func components(
        probabilities: [Float],
        width: Int,
        height: Int,
        originalWidth: Int,
        originalHeight: Int
    ) -> [PaddleOCRBox] {
        var visited = [Bool](repeating: false, count: width * height)
        var boxes: [PaddleOCRBox] = []
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                guard !visited[idx], probabilities[idx] >= threshold else { continue }
                let comp = floodFill(
                    startX: x, startY: y,
                    probabilities: probabilities,
                    visited: &visited,
                    width: width,
                    height: height)
                guard comp.count > 8, comp.score >= boxThreshold else { continue }
                let sx = CGFloat(originalWidth) / CGFloat(width)
                let sy = CGFloat(originalHeight) / CGFloat(height)
                let pad = CGFloat(max(comp.maxY - comp.minY, comp.maxX - comp.minX)) * 0.12
                let rect = CGRect(
                    x: CGFloat(comp.minX) * sx - pad,
                    y: CGFloat(comp.minY) * sy - pad,
                    width: CGFloat(comp.maxX - comp.minX + 1) * sx + pad * 2,
                    height: CGFloat(comp.maxY - comp.minY + 1) * sy + pad * 2
                ).intersection(CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
                guard rect.width > 3, rect.height > 3 else { continue }
                boxes.append(PaddleOCRBox(rect: rect, confidence: comp.score))
            }
        }
        return boxes
    }

    private func floodFill(
        startX: Int,
        startY: Int,
        probabilities: [Float],
        visited: inout [Bool],
        width: Int,
        height: Int
    ) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, score: Float, count: Int) {
        var stack = [(startX, startY)]
        var minX = startX
        var maxX = startX
        var minY = startY
        var maxY = startY
        var sum: Float = 0
        var count = 0
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            let idx = y * width + x
            guard !visited[idx], probabilities[idx] >= threshold else { continue }
            visited[idx] = true
            count += 1
            sum += probabilities[idx]
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    stack.append((x + dx, y + dy))
                }
            }
        }
        return (minX, minY, maxX, maxY, count > 0 ? sum / Float(count) : 0, count)
    }

    private static func resizedSize(width: Int, height: Int) -> (Int, Int) {
        let limit = 64.0
        let maxSide = 4000.0
        var ratio = min(width, height) < Int(limit) ? limit / Double(min(width, height)) : 1
        if Double(max(width, height)) * ratio > maxSide {
            ratio = maxSide / Double(max(width, height))
        }
        let w = max(32, Int((Double(width) * ratio / 32).rounded(.toNearestOrEven)) * 32)
        let h = max(32, Int((Double(height) * ratio / 32).rounded(.toNearestOrEven)) * 32)
        return (w, h)
    }

    private static func floats(from data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}
