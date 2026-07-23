#if DEBUG
import AppKit
import CoreGraphics
import ResponsayCore

/// DEBUG-only：不经真实框选就弹出截图取字 面板，给设计走查 / 截图用。
/// 触发：`responsay://snap-ocr-fixture`。Release 编译不含此文件。
@MainActor
enum SnapOCRFixture {

    /// 故意混排：item 2 拆成两行（小行距 → 智能分段会合并），其余大行距各自成段，
    /// 这样切「智能分段 / 原始分行」肉眼可见差别。
    private static let lines = [
        "截图取字 结果窗口示例，太。",
        "2. 云端模型取字功能太差，可以去掉，OCR 还是要用专",   // 续行 ↓
        "门的 OCR 模型。",
        "3. 截图取字窗口可以更换服务商。",
        "4. 点击 Dock 上的图标，需要可以启动主窗口。",
        "5. claude design 和 gpt5.5 提示词优化",
    ]
    /// 与 `lines` 一一对应：与上一行的垂直间距。2 = 续行（同段），26 = 断段（行高 22、阈值 ≈17.6）。
    private static let gaps: [CGFloat] = [0, 26, 2, 26, 26, 26]

    static func show() {
        let (result, image) = sample()
        SnapOCRPanel.shared.show(result: result, image: image)
    }

    private static func sample() -> (OCRResult, CGImage) {
        var regions: [OCRRegion] = []
        var y: CGFloat = 16
        for (line, gap) in zip(lines, gaps) {
            y += gap
            regions.append(OCRRegion(
                text: line, boundingBox: CGRect(x: 20, y: y, width: 540, height: 22), confidence: 0.95))
            y += 22
        }
        let result = OCRResult(regions: regions, languages: ["zh-Hans", "en-US"])
        let image = render(size: CGSize(width: 580, height: y + 16)) ?? blank()
        return (result, image)
    }

    private static func render(size: CGSize) -> CGImage? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black]
        var y = size.height - 38
        for (line, gap) in zip(lines, gaps) {
            y -= gap * 0.9
            (line as NSString).draw(at: NSPoint(x: 22, y: y), withAttributes: attrs)
            y -= 22
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func blank() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
#endif
