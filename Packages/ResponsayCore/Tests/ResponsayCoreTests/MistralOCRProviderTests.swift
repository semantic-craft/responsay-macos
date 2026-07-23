import CoreGraphics
import Foundation
import Testing
@testable import ResponsayCore

// Mistral OCR provider (dedicated document OCR, returns Markdown). Real HTTP is E2E (needs a key);
// here we cover the pure seams — response parsing, Markdown → plain text, and the injected path.
struct MistralOCRProviderTests {

    private func tinyImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()!
    }

    /// Multi-page response: join non-empty pages (Markdown kept).
    @Test func parseJoinsNonEmptyPagesKeepingMarkdown() throws {
        let json = ##"{"pages":[{"markdown":"# 标题"},{"markdown":"  "},{"markdown":"正文"}]}"##
        let text = try MistralOCRProvider.parseOCRResponse(Data(json.utf8), keepMarkdown: true)
        #expect(text == "# 标题\n\n正文")
    }

    /// Default strips Markdown → plain text (heading/emphasis/link/code markup gone).
    @Test func parseStripsMarkdownToPlainText() throws {
        let json = ##"{"pages":[{"markdown":"# 标题\n**粗体** 与 [链接](http://x) 和 `代码`"}]}"##
        let text = try MistralOCRProvider.parseOCRResponse(Data(json.utf8), keepMarkdown: false)
        #expect(text == "标题\n粗体 与 链接 和 代码")
    }

    /// Empty pages → empty string (capture pipeline shows "not recognized").
    @Test func parseEmptyPagesYieldsEmpty() throws {
        let text = try MistralOCRProvider.parseOCRResponse(Data(#"{"pages":[]}"#.utf8), keepMarkdown: false)
        #expect(text.isEmpty)
    }

    /// Endpoint appends `/v1/ocr` and tolerates a trailing slash.
    @Test func endpointAppendsOCRPath() {
        #expect(MistralOCRProvider.endpoint(apiURL: "https://api.mistral.ai")?.absoluteString
            == "https://api.mistral.ai/v1/ocr")
        #expect(MistralOCRProvider.endpoint(apiURL: "https://api.mistral.ai/")?.absoluteString
            == "https://api.mistral.ai/v1/ocr")
    }

    /// Markdown → plain text pure function: common markup cleanup.
    @Test func markdownPlainText() {
        #expect(MarkdownPlainText.from("## 二级标题") == "二级标题")
        #expect(MarkdownPlainText.from("- 项目一\n- 项目二") == "项目一\n项目二")
        #expect(MarkdownPlainText.from("![图](x.png) 后文") == "图 后文")
        #expect(MarkdownPlainText.from("***重点***") == "重点")
    }

    /// Injected transcriber: recognize packs the transcript into OCRResult (no per-line boxes).
    @Test func recognizeUsesStub() async throws {
        let provider = MistralOCRProvider { _, _ in "Mistral 转写正文" }
        let result = try await provider.recognize(tinyImage())
        #expect(result.text == "Mistral 转写正文")
        #expect(result.regions.isEmpty)
        #expect(result.textStructure == .flowedText)
        #expect(!result.supportsSmartParagraphing)
        #expect(!result.isEmpty)
    }

    /// Unconfigured key (apiKeyProvider returns nil) → recognize throws `.notConfigured`, no network.
    @Test func notConfiguredThrows() async {
        let provider = MistralOCRProvider(apiKeyProvider: { nil })
        await #expect(throws: CloudOCRError.notConfigured) {
            _ = try await provider.recognize(tinyImage())
        }
    }

    @Test func engineIdentity() {
        #expect(MistralOCRProvider { _, _ in "" }.id == "mistral-ocr")
    }
}
