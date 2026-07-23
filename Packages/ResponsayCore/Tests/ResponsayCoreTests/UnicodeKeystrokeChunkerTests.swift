import Testing
@testable import ResponsayCore

/// INSERT-UNICODE-004: chunk under the CGEvent ~20-UTF16-unit cap without splitting graphemes.
@Suite struct UnicodeKeystrokeChunkerTests {
    @Test func chunksStayUnderCapAndAreLossless() {
        let text = String(repeating: "你", count: 50)  // 50 UTF-16 units
        let chunks = UnicodeKeystrokeChunker.chunks(text, maxUnits: 18)
        #expect(chunks.allSatisfy { $0.count <= 18 })
        #expect(chunks.flatMap { $0 } == Array(text.utf16))   // reconstructs exactly
    }

    @Test func neverSplitsGraphemeClusters() {
        let family = "👨‍👩‍👧‍👦"     // ZWJ sequence, 11 UTF-16 units
        let combining = "a\u{0301}"   // base + combining acute
        let text = family + combining + family + "hello"
        let chunks = UnicodeKeystrokeChunker.chunks(text, maxUnits: 18)
        #expect(chunks.allSatisfy { $0.count <= 18 })
        #expect(chunks.flatMap { $0 } == Array(text.utf16))
    }

    @Test func oversizeSingleGraphemeStaysWhole() {
        let family = "👨‍👩‍👧‍👦"  // 11 units, larger than the cap below
        let chunks = UnicodeKeystrokeChunker.chunks(family, maxUnits: 4)
        #expect(chunks.count == 1)
        #expect(chunks[0] == Array(family.utf16))   // not split, even over cap
    }

    @Test func emptyTextProducesNoChunks() {
        #expect(UnicodeKeystrokeChunker.chunks("").isEmpty)
    }
}
