import XCTest
@testable import ResponsayMac

/// Pins the only pure seam of the Qwen3-local soft-biasing wiring (#500 S1): how biasing terms are
/// projected into sherpa-onnx's comma-separated `hotwords` model-config string. The recognizer
/// init itself loads ONNX (device-only), so this formatter is the unit we can guard.
final class Qwen3ASRHotwordsTests: XCTestCase {

    func testJoinsTermsWithAsciiComma() {
        XCTAssertEqual(
            Qwen3ASRRecognizer.hotwordsString(from: ["请求权基础", "Westlaw", "卡尔·拉伦茨"]),
            "请求权基础,Westlaw,卡尔·拉伦茨")
    }

    func testEmptyTermsYieldEmptyString() {
        XCTAssertEqual(Qwen3ASRRecognizer.hotwordsString(from: []), "")
    }

    /// A term containing the ASCII separator would corrupt the list — strip it, don't split on it.
    func testStripsEmbeddedCommasSoSeparatorStaysIntact() {
        XCTAssertEqual(
            Qwen3ASRRecognizer.hotwordsString(from: ["a,b", "c"]),
            "ab,c")
    }

    /// Terms that reduce to empty after stripping are dropped (no stray separators).
    func testDropsTermsThatBecomeEmpty() {
        XCTAssertEqual(
            Qwen3ASRRecognizer.hotwordsString(from: ["", ",", "term"]),
            "term")
    }
}
