import Foundation
import Testing
@testable import ResponsayCore

/// 515 — 整理 prompt 携带词典热词 + 疑似听错纠正指令。
/// The dictionary line rides `transformContextBlock` (shared by 整理/翻译/改写); the mishear-
/// correction instruction is polish-only and appears ONLY when a context block is present, so
/// 词典空 + 屏幕上下文 OFF keeps the prompt byte-identical to the pre-515 shape.
struct TransformContextDictionaryLineTests {
    private func fixtureContext(hotwords: [String] = []) -> ExpressionContext {
        ExpressionContext(
            appName: "Xcode",
            windowTitle: "ResponsayCore",
            textBeforeCursor: "前文",
            textAfterCursor: "后文",
            browserURL: "https://example.com/a",
            visibleScreenText: "屏幕正文",
            hotwords: hotwords)
    }

    @Test func dictionaryLineSitsAfterURLAndBeforeCursorText() {
        let block = ExpressPromptBuilder.transformContextBlock(
            fixtureContext(hotwords: ["Matt Pocock", "Qwen3-ASR"]))

        #expect(block?.contains(
            "网页地址：https://example.com/a\n用户词典/专有名词：Matt Pocock, Qwen3-ASR\n光标前文字：前文") == true)
    }

    @Test func acceptanceFixtureDictionaryPlusMishearInstructionReachPolishPrompt() {
        // 词典含 Matt Pocock，输入是一次真实 wild miss（Metapocalypse）→ 组装出的 prompt 同时
        // 含词典行与纠正指令（纯组装断言，无网络）。
        let block = ExpressPromptBuilder.transformContextBlock(
            fixtureContext(hotwords: ["Matt Pocock"]))
        let prompt = PolishPromptBuilder.build(
            text: "我想说的是 Metapocalypse 的技能",
            context: block)

        let assembled = prompt.system + "\n" + prompt.user
        #expect(assembled.contains("用户词典/专有名词：Matt Pocock"))
        #expect(assembled.contains("Mishear correction"))
        #expect(assembled.contains("不得引入词典与上下文中都不存在的新名字"))
    }

    @Test func emptyDictionaryEmitsExactPreexistingBlock() {
        // 回归钉死：词典为空 → 无词典行，块与 515 之前的格式逐字一致。
        let block = ExpressPromptBuilder.transformContextBlock(fixtureContext())

        #expect(block == [
            "当前应用：Xcode",
            "窗口标题：ResponsayCore",
            "网页地址：https://example.com/a",
            "光标前文字：前文",
            "光标后文字：后文",
            "屏幕可见内容：屏幕正文",
        ].joined(separator: "\n"))
    }

    @Test func nilContextKeepsPolishPromptFreeOfNewMarkers() {
        // 词典为空且屏幕上下文 OFF → transformContext 为 nil → prompt 不含任何 515 新增痕迹
        //（配合全量既有组装测试绿 = 字节一致回归）。
        let prompt = PolishPromptBuilder.build(text: "hello world", context: nil)

        let assembled = prompt.system + "\n" + prompt.user
        #expect(!assembled.contains("用户词典/专有名词"))
        #expect(!assembled.contains("Mishear correction"))
        #expect(!assembled.contains("不得引入词典与上下文中都不存在的新名字"))
    }

    @Test func dictionaryLineCapsAtFortyTermsAndEightyCharacters() {
        // 直接改 hotwords 绕过 ExpressionContext.init 的清洗，验证词典行自身的上限。
        var context = fixtureContext()
        context.hotwords = [String(repeating: "a", count: 100)] + (1...44).map { "Word\($0)" }

        let block = ExpressPromptBuilder.transformContextBlock(context) ?? ""
        #expect(block.contains(String(repeating: "a", count: 80)))
        #expect(!block.contains(String(repeating: "a", count: 81)))
        #expect(block.contains("Word39"))   // 1 long + Word1…Word39 = 40 terms
        #expect(!block.contains("Word40"))
    }

    @Test func mishearInstructionIsPolishOnlyAndContextGated() {
        let context = "当前应用：Xcode\n用户词典/专有名词：Matt Pocock"

        let polishWithContext = TextTransformPromptAssembler.build(
            action: .polish, text: "x", input: .rawTranscript, output: .jsonTextChanges,
            options: .init(context: context))
        #expect(polishWithContext.system.contains("Mishear correction"))

        let polishNoContext = TextTransformPromptAssembler.build(
            action: .polish, text: "x", input: .rawTranscript, output: .jsonTextChanges)
        #expect(!polishNoContext.system.contains("Mishear correction"))

        let translate = TextTransformPromptAssembler.build(
            action: .translate(target: .englishUS), text: "x", input: .rawTranscript,
            output: .jsonTextChanges, options: .init(context: context))
        #expect(!translate.system.contains("Mishear correction"))

        let rewrite = TextTransformPromptAssembler.build(
            action: .rewrite(style: .tone(.natural)), text: "x", input: .selectedText,
            output: .jsonTextChanges, options: .init(context: context))
        #expect(!rewrite.system.contains("Mishear correction"))
    }

    @Test func registerFollowLineAppearsOnlyWithContextBlock() {
        let block = ExpressPromptBuilder.transformContextBlock(fixtureContext())
        let withContext = PolishPromptBuilder.build(text: "占位", context: block)
        let withoutContext = PolishPromptBuilder.build(text: "占位", context: nil)

        #expect(withContext.system.contains("Register follow"))
        #expect(!withoutContext.system.contains("Register follow"))

        // polish-only：翻译/改写即使带同一份上下文块也不出现（同 mishear 的门控形状）。
        let context = block ?? ""
        let translate = TextTransformPromptAssembler.build(
            action: .translate(target: .englishUS), text: "占位", input: .rawTranscript,
            output: .jsonTextChanges, options: .init(context: context))
        #expect(!translate.system.contains("Register follow"))

        let rewrite = TextTransformPromptAssembler.build(
            action: .rewrite(style: .tone(.natural)), text: "占位", input: .selectedText,
            output: .jsonTextChanges, options: .init(context: context))
        #expect(!rewrite.system.contains("Register follow"))
    }
}
