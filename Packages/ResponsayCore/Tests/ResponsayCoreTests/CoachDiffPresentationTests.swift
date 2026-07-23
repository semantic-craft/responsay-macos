import Testing
@testable import ResponsayCore

struct CoachDiffPresentationTests {
    @Test func english_source_yields_segmented_diff() {
        let p = CoachDiffPresentation.make(original: "I very like this idea",
                                           idiomatic: "I really like this idea")
        #expect(p == .diff([
            DiffSegment("I", .same), DiffSegment("very", .deleted),
            DiffSegment("really", .inserted), DiffSegment("like", .same),
            DiffSegment("this", .same), DiffSegment("idea", .same),
        ]))
    }

    @Test func chinese_source_yields_source_quote_no_diff() {
        let p = CoachDiffPresentation.make(original: "我想委婉提醒对方",
                                           idiomatic: "Could you remind them gently?")
        #expect(p == .sourceQuote("我想委婉提醒对方"))
    }

    @Test func pure_insertion_marks_only_inserted() {
        let p = CoachDiffPresentation.make(original: "give me advice",
                                           idiomatic: "give me some advice")
        #expect(p == .diff([
            DiffSegment("give", .same), DiffSegment("me", .same),
            DiffSegment("some", .inserted), DiffSegment("advice", .same),
        ]))
    }
}
