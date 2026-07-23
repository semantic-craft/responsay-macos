import CoreGraphics
import Foundation
import ResponsayCore

struct PaddleOCRImage: Sendable {
    let width: Int
    let height: Int
    let rgb: [UInt8]

    init(cgImage: CGImage, width: Int? = nil, height: Int? = nil) throws {
        let targetW = width ?? cgImage.width
        let targetH = height ?? cgImage.height
        guard targetW > 0, targetH > 0 else {
            throw OCRError.recognitionFailed("截图区域为空。")
        }
        self.width = targetW
        self.height = targetH

        var rgba = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OCRError.recognitionFailed("无法准备 OCR 图像。")
        }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(targetH))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        var out = [UInt8](repeating: 0, count: targetW * targetH * 3)
        for i in 0..<(targetW * targetH) {
            out[i * 3] = rgba[i * 4]
            out[i * 3 + 1] = rgba[i * 4 + 1]
            out[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.rgb = out
    }

    func detectionTensor() -> Data {
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]
        let plane = width * height
        var floats = [Float](repeating: 0, count: plane * 3)
        for i in 0..<plane {
            for c in 0..<3 {
                let v = Float(rgb[i * 3 + c]) / 255
                floats[c * plane + i] = (v - mean[c]) / std[c]
            }
        }
        return Self.data(from: floats)
    }

    func recognitionTensor(targetHeight: Int = 48, maxWidth: Int = 3200) -> (Data, [NSNumber]) {
        let ratio = width > 0 && height > 0 ? Double(width) / Double(height) : 1
        let targetW = min(maxWidth, max(1, Int(ceil(Double(targetHeight) * ratio))))
        let resized = try? PaddleOCRImage(cgImage: makeCGImage(), width: targetW, height: targetHeight)
        let image = resized ?? self
        let plane = image.width * image.height
        var floats = [Float](repeating: 0, count: plane * 3)
        for i in 0..<plane {
            for c in 0..<3 {
                floats[c * plane + i] = Float(image.rgb[i * 3 + c]) / 127.5 - 1
            }
        }
        let shape: [NSNumber] = [
            NSNumber(value: 1), NSNumber(value: 3),
            NSNumber(value: image.height), NSNumber(value: image.width),
        ]
        return (Self.data(from: floats), shape)
    }

    private func makeCGImage() -> CGImage {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb[i * 3]
            rgba[i * 4 + 1] = rgb[i * 3 + 1]
            rgba[i * 4 + 2] = rgb[i * 3 + 2]
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)!
    }

    private static func data(from floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
    }
}
