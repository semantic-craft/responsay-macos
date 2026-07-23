import CoreGraphics
import Foundation

/// 取字排版模式：智能分段 ↔ 原始分行。`rawValue` 供面板切换 + 偏好持久化复用。
/// (Ported from anamra's Core — the 截图 OCR panel's paragraphing toggle.)
public enum OCRLayoutMode: String, Codable, Sendable, CaseIterable, Hashable {
    case smart   // 智能分段：行距小合并为段、中文不插空格
    case raw     // 原始分行：每行一行，逐行换行

    public var label: String {
        switch self {
        case .smart: return "智能分段"
        case .raw: return "原始分行"
        }
    }
}

/// 智能分段（纯函数）：把逐行 OCR `OCRRegion` 组装成可读文本。
///
/// 智能分段以**行间垂直间距**为主信号——间距小于行高 × 阈值视为同段续行，否则断为新段；
/// 续行拼接按语言决定是否插空格（中文无空格、英文有空格）。脱离 Vision、可单测，是取字质量核心。
public enum OCRParagraphAssembler {

    /// 段落断裂阈值：行间垂直间距 > 行高 × 此系数 → 视为新段落。
    private static let paragraphGapFactor: CGFloat = 0.8
    /// 句末标点只在已有可见行距时增强断段，不把同一紧凑文本块拆成逐句列表。
    private static let punctuationGapFactor: CGFloat = 0.3

    public static func text(from regions: [OCRRegion], mode: OCRLayoutMode) -> String {
        // 按 box 顶边从上到下排序（像素空间原点左上）。
        let ordered = regions.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        guard !ordered.isEmpty else { return "" }
        switch mode {
        case .raw:
            return ordered.map(\.text).joined(separator: "\n")
        case .smart:
            return assembleRegionLines(ordered)
        }
    }

    public static func text(fromRawLines text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var paragraph = ""
        var previousLine = ""
        var previousEndedSoftHyphen = false
        var isInsideFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append(paragraph)
            paragraph = ""
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let endedSoftHyphen = rawLine.trimmingCharacters(in: .whitespaces).last == "\u{00AD}"
            let withoutSoftHyphen = rawLine.replacingOccurrences(of: "\u{00AD}", with: "")
            let line = withoutSoftHyphen.trimmingCharacters(in: .whitespaces)
            let isFenceDelimiter = isFenceDelimiter(line)

            if isInsideFence || isFenceDelimiter {
                flushParagraph()
                output.append(rawLine)
                if isFenceDelimiter { isInsideFence.toggle() }
                previousLine = ""
                previousEndedSoftHyphen = false
                continue
            }

            if line.isEmpty {
                flushParagraph()
                if output.last != "" { output.append("") }
                previousLine = ""
                previousEndedSoftHyphen = false
                continue
            }

            if isStructural(rawLine) {
                flushParagraph()
                output.append(withoutSoftHyphen)
                previousLine = ""
                previousEndedSoftHyphen = false
                continue
            }

            if paragraph.isEmpty {
                paragraph = line
            } else if endsParagraph(previousLine) {
                flushParagraph()
                paragraph = line
            } else {
                let joiner = previousEndedSoftHyphen ? "" : separator(after: paragraph, before: line)
                paragraph += joiner + line
            }
            previousLine = rawLine
            previousEndedSoftHyphen = endedSoftHyphen
        }
        flushParagraph()
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    private static func assembleRegionLines(_ ordered: [OCRRegion]) -> String {
        var paragraphs: [String] = []
        var current = ""
        var isInsideFence = false

        func flushCurrent() {
            guard !current.isEmpty else { return }
            paragraphs.append(current)
            current = ""
        }

        for index in ordered.indices {
            let currentText = ordered[index].text
            let isFenceDelimiter = isFenceDelimiter(currentText)

            if isInsideFence || isFenceDelimiter {
                flushCurrent()
                paragraphs.append(currentText)
                if isFenceDelimiter { isInsideFence.toggle() }
                continue
            }

            if isStructural(currentText) {
                flushCurrent()
                paragraphs.append(currentText)
                continue
            }

            guard !current.isEmpty else {
                current = currentText
                continue
            }

            let prev = ordered[index - 1].boundingBox
            let cur = ordered[index].boundingBox
            let gap = cur.minY - prev.maxY
            let lineHeight = max(prev.height, 1)
            let previousText = ordered[index - 1].text
            let punctuationBreak = endsParagraph(previousText)
                && gap > lineHeight * punctuationGapFactor
            if gap > lineHeight * paragraphGapFactor
                || punctuationBreak
                || isStructural(previousText) {
                flushCurrent()                          // 大行距 → 断新段
                current = currentText
            } else {
                current += separator(after: current, before: currentText)
                    + currentText                      // 续行
            }
        }
        flushCurrent()
        return paragraphs.joined(separator: "\n")
    }

    /// 续行拼接分隔符：任一侧为 CJK → 不插空格；纯拉丁 → 插一个空格。
    private static func separator(after left: String, before right: String) -> String {
        guard let l = left.last, let r = right.first else { return "" }
        if OCRTextScript.isCJK(l) || OCRTextScript.isCJK(r) { return "" }
        return " "
    }

    private static func isStructural(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.first?.isWhitespace == true { return true }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if isFenceDelimiter(trimmed) || trimmed.contains("|") || trimmed.contains("\t") {
            return true
        }
        if trimmed.range(of: #"\s{2,}"#, options: .regularExpression) != nil {
            return true
        }
        return trimmed.range(
            of: #"^(?:[-*•▪◦]\s*|\d+[.)、]\s*|[（(]?[一二三四五六七八九十]+[、.)）]\s*|[A-Za-z][.)]\s+)"#,
            options: .regularExpression) != nil
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func endsParagraph(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return false }
        return "。！？!?；;:：.".contains(last)
    }
}
