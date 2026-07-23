import XCTest
@testable import ResponsayMac
import ResponsayCore

final class SnapTranslateSessionTests: XCTestCase {

    @MainActor
    func testEditingSourceMarksTranslationStaleWithoutAutomaticRequest() async {
        let original = OCRResult(
            text: "原文",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .flowedText)
        let session = SnapTranslateSession(original: original)
        var requestedTexts: [String] = []

        _ = await session.translate(serviceId: "qwen", target: .englishUS) { text, _, _ in
            requestedTexts.append(text)
            return .success("first translation")
        }
        XCTAssertEqual(requestedTexts, ["原文"])
        XCTAssertFalse(session.isTranslationStale(serviceId: "qwen", target: .englishUS))

        session.draft.text = "编辑后的原文"
        XCTAssertTrue(session.isTranslationStale(serviceId: "qwen", target: .englishUS))
        XCTAssertEqual(requestedTexts, ["原文"])

        _ = await session.translate(serviceId: "qwen", target: .englishUS) { text, _, _ in
            requestedTexts.append(text)
            return .success("updated translation")
        }
        XCTAssertEqual(requestedTexts, ["原文", "编辑后的原文"])
        XCTAssertEqual(session.output, "updated translation")
        XCTAssertFalse(session.isTranslationStale(serviceId: "qwen", target: .englishUS))
    }

    @MainActor
    func testChangingServiceMakesDisplayedTranslationStale() async {
        let original = OCRResult(
            text: "原文",
            regions: [],
            languages: ["zh-Hans"],
            textStructure: .flowedText)
        let session = SnapTranslateSession(original: original)

        _ = await session.translate(serviceId: "qwen", target: .englishUS) { _, _, _ in
            .success("qwen translation")
        }

        XCTAssertFalse(session.isTranslationStale(serviceId: "qwen", target: .englishUS))
        XCTAssertTrue(session.isTranslationStale(serviceId: "mimo", target: .englishUS))
    }

    @MainActor
    func testChangingLayoutWaitsForExplicitRetranslation() async {
        let original = OCRResult(
            text: "first\ncontinuation",
            regions: [],
            languages: ["en-US"],
            textStructure: .rawLines)
        let session = SnapTranslateSession(original: original)
        var requestedTexts: [String] = []

        _ = await session.translate(serviceId: "qwen", target: .chineseSimplified) { text, _, _ in
            requestedTexts.append(text)
            return .success("首次译文")
        }

        session.draft.select(.raw)
        XCTAssertTrue(session.isTranslationStale(serviceId: "qwen", target: .chineseSimplified))
        XCTAssertEqual(requestedTexts, ["first continuation"])

        _ = await session.translate(serviceId: "qwen", target: .chineseSimplified) { text, _, _ in
            requestedTexts.append(text)
            return .success("更新译文")
        }
        XCTAssertEqual(requestedTexts, ["first continuation", "first\ncontinuation"])
    }
}
