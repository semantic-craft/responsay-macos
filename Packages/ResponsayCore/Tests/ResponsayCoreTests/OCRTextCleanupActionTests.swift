import Testing
@testable import ResponsayCore

struct OCRTextCleanupActionTests {

    @Test func chinesePunctuation_onlyConvertsPunctuationBorderingCJK() {
        let source = "你好,世界! 版本3.14, URL https://例子.测试/路径?查询=1 `字段:类型` 条款:有效"

        #expect(OCRTextCleanupAction.chinesePunctuation.apply(to: source)
            == "你好，世界！ 版本3.14, URL https://例子.测试/路径?查询=1 `字段:类型` 条款：有效")
    }

    @Test func chinesePunctuation_protectsOnlyURLAndEmailSpans() {
        let source = "见https://例子.测试,然后发至用户@example.com,继续"

        #expect(OCRTextCleanupAction.chinesePunctuation.apply(to: source)
            == "见https://例子.测试，然后发至用户@example.com，继续")
    }

    @Test func chinesePunctuation_preservesFencedAndMemberAccessCode() {
        let source = "```swift\n对象.method()\n```\n调用对象.method(),然后继续"

        #expect(OCRTextCleanupAction.chinesePunctuation.apply(to: source)
            == "```swift\n对象.method()\n```\n调用对象.method()，然后继续")
    }

    @Test func chinesePunctuation_convertsSentenceMarksAfterMemberAccess() {
        let source = "调用对象.method().然后 调用对象.method():继续"

        #expect(OCRTextCleanupAction.chinesePunctuation.apply(to: source)
            == "调用对象.method()。然后 调用对象.method()：继续")
    }

    @Test func englishPunctuation_convertsOnlyTheSixDeclaredFullWidthForms() {
        let source = "你好，世界！「引用」版本3。14；状态：有效？"

        #expect(OCRTextCleanupAction.englishPunctuation.apply(to: source)
            == "你好,世界!「引用」版本3.14;状态:有效?")
    }

    @Test func cjkSpacing_removesOnlyWhitespaceBetweenCJKCharacters() {
        let source = "中 文　字 mixed words 日 本\n  缩进 保留"

        #expect(OCRTextCleanupAction.cjkSpacing.apply(to: source)
            == "中文字 mixed words 日本\n  缩进保留")
    }
}
