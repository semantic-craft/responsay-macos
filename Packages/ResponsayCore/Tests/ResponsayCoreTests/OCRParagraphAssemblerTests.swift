import CoreGraphics
import Foundation
import Testing
@testable import ResponsayCore

/// 截图 OCR · 段落重排：智能分段（按行距合并续行、中文不插空格、英文插空格）↔ 原始分行。
/// 纯函数，脱离 Vision，钉死 `displayText(mode:)` 的两条出口（本机有 box / 云端纯文本回落）。
struct OCRParagraphAssemblerTests {

    /// 行高 10、x 不变；`gapAbove` = 与上一行底边的垂直间距。
    private func line(_ text: String, y: CGFloat, height: CGFloat = 10) -> OCRRegion {
        OCRRegion(text: text, boundingBox: CGRect(x: 0, y: y, width: 100, height: height), confidence: 1)
    }

    @Test func raw_joinsEveryLineWithNewline() {
        let regions = [line("第一行", y: 0), line("第二行", y: 11), line("第三行", y: 22)]
        #expect(OCRParagraphAssembler.text(from: regions, mode: .raw) == "第一行\n第二行\n第三行")
    }

    @Test func smart_mergesTightLines_breaksOnWideGap() {
        // 行高 10、阈值 0.8 → gap ≤ 8 续行、> 8 断段。
        let regions = [
            line("续行甲", y: 0),          // 段 1
            line("续行乙", y: 13),         // gap 3 → 同段（中文无空格拼接）
            line("新段开头", y: 40),       // gap 17 → 断新段
        ]
        #expect(OCRParagraphAssembler.text(from: regions, mode: .smart) == "续行甲续行乙\n新段开头")
    }

    @Test func smart_insertsSpaceBetweenLatinLines() {
        let regions = [line("hello", y: 0), line("world", y: 12)]   // gap 2 → 续行，拉丁插空格
        #expect(OCRParagraphAssembler.text(from: regions, mode: .smart) == "hello world")
    }

    @Test func displayText_fallsBackToRawText_whenNoRegions() {
        // 云端引擎只给整段文本、无 box → 排版切换是安全回落，两模式都给原文。
        let cloud = OCRResult(text: "云端纯文本", regions: [], languages: ["zh-Hans"])
        #expect(cloud.displayText(mode: .smart) == "云端纯文本")
        #expect(cloud.displayText(mode: .raw) == "云端纯文本")
    }

    @Test func rawLineResult_smartMergesContinuation_withoutBoxes() {
        let result = OCRResult(
            text: "这是第一行\n这是续行",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .rawLines)

        #expect(result.supportsSmartParagraphing)
        #expect(result.displayText(mode: .smart) == "这是第一行这是续行")
        #expect(result.displayText(mode: .raw) == "这是第一行\n这是续行")
    }

    @Test func rawLineResult_preservesBlankLinesListsAndColonBoundaries() {
        let result = OCRResult(
            text: "第一行\n续行\n\n1. 第一项\n2. 第二项\n说明：\n详情",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .rawLines)

        #expect(result.displayText(mode: .smart) == "第一行续行\n\n1. 第一项\n2. 第二项\n说明：\n详情")
    }

    @Test func regionResult_usesPunctuationWithModerateGap_asParagraphBoundary() {
        let regions = [line("第一句。", y: 0), line("第二句", y: 14)]

        #expect(OCRParagraphAssembler.text(from: regions, mode: .smart) == "第一句。\n第二句")
    }

    @Test func rawLineResult_removesLineEndingSoftHyphenWithoutAddingSpace() {
        let result = OCRResult(
            text: "soft\u{00AD}\nware",
            regions: [],
            languages: ["en-US"],
            textStructure: .rawLines)

        #expect(result.displayText(mode: .smart) == "software")
    }

    @Test func rawLineResult_preservesFencedCodeAndIndentation() {
        let result = OCRResult(
            text: "```swift\nlet first = 1\nlet second = 2\n```\n  indented\nfollowing\nline",
            regions: [],
            languages: ["en-US"],
            textStructure: .rawLines)

        #expect(result.displayText(mode: .smart) == "```swift\nlet first = 1\nlet second = 2\n```\n  indented\nfollowing line")
    }

    @Test func singleRawLineResult_stillSupportsSmartParagraphing() {
        let result = OCRResult(
            text: "single line",
            regions: [],
            languages: ["en-US"],
            textStructure: .rawLines)

        #expect(result.supportsSmartParagraphing)
    }

    @Test func regionResult_preservesFencedCodeLines() {
        let regions = [
            line("```swift", y: 0),
            line("let first = 1", y: 12),
            line("let second = 2", y: 24),
            line("```", y: 36),
        ]

        #expect(OCRParagraphAssembler.text(from: regions, mode: .smart) == "```swift\nlet first = 1\nlet second = 2\n```")
    }

    @Test func regionResult_preservesTableRowsWithEmbeddedPipes() {
        let regions = [
            line("Name | Value", y: 0),
            line("Alice | 1", y: 12),
        ]

        #expect(OCRParagraphAssembler.text(from: regions, mode: .smart) == "Name | Value\nAlice | 1")
    }
}
