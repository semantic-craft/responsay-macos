import Testing
@testable import ResponsayCore

@Suite("RecentASRContextBuffer")
struct RecentASRContextBufferTests {
    @Test func isolatesAppsBoundsHistoryAndOnlyAppliesAliasesToOutgoingCopies() {
        var buffer = RecentASRContextBuffer()
        for index in 1...6 {
            buffer.record("Notes turn \(index): matis", scope: "com.apple.Notes")
        }
        buffer.record("Chat turn", scope: "com.tencent.xinWeChat")

        #expect(buffer.context(for: "com.tencent.xinWeChat") == ["Chat turn"])
        #expect(buffer.context(for: "com.apple.Notes") == (2...6).map { "Notes turn \($0): matis" })
        #expect(buffer.context(
            for: "com.apple.Notes",
            learnedAliases: ["matis": "Metis"]) == (2...6).map { "Notes turn \($0): Metis" })
        #expect(buffer.context(for: "com.apple.Notes").last == "Notes turn 6: matis")
    }
}
