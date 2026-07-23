import AppKit

// MARK: - 截图复制 · 把框选图片写入剪贴板
//
// 放三种表示，让不同目标各取所需（recipe 同 anamra ScreenCopyCoordinator）：
// - **PNG 字节**：备忘录 / 微信 / 预览 / 邮件 / 图片编辑器 → 直接贴图。
// - **文件 URL**：终端里的 Claude Code、上传控件 → 当文件路径 / 附件抓取。
// - **普通文本**：临时 PNG 的 file:// URL，文本框里粘贴就是路径。
// 先声明 PNG，避免富文本 / 聊天类目标优先拿 URL 文本而贴成一行。不取字、不翻译、不联网。
enum ClipboardImageWriter {
    private static let tempPrefix = "Responsay-clip-"
    private static let tempSuffix = ".png"
    private static let retention: TimeInterval = 24 * 60 * 60

    @MainActor
    static func write(_ cgImage: CGImage) {
        let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        if let png {
            item.setData(png, forType: .png)
            // file:// URL is best-effort: if the temp write fails the image still copies.
            if let url = writeTempPNG(png) {
                item.setString(url.absoluteString, forType: .fileURL)
                item.setString(url.absoluteString, forType: .string)
            }
        }
        pb.writeObjects([item])
    }

    /// Persist a temp PNG the clipboard's file:// URL points at — can't delete now, the
    /// pasteboard references it. Prune our own >24h leftovers on each write so they don't leak.
    private static func writeTempPNG(_ png: Data) -> URL? {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        pruneExpired(in: dir)
        let url = dir.appendingPathComponent("\(tempPrefix)\(UUID().uuidString)\(tempSuffix)")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func pruneExpired(in dir: URL) {
        let cutoff = Date().addingTimeInterval(-retention)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix(tempPrefix), name.hasSuffix(tempSuffix) else { continue }
            let modified = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}
