import Testing
import Foundation
@testable import ResponsayCore

/// 179 — `CoachRegister` (教练语域) decode + default resolution. Mirrors the `RewriteTone`
/// tolerant-decode test; the default is `.casual` (口语) so the Coach's original behavior holds.
struct CoachRegisterTests {
    @Test func decodes_allFourValues() throws {
        struct Wrapper: Decodable { let register: CoachRegister }
        for (raw, expected): (String, CoachRegister) in [
            ("casual", .casual), ("neutral", .neutral), ("formal", .formal), ("academic", .academic),
        ] {
            let json = #"{"register":"\#(raw)"}"#.data(using: .utf8)!
            let w = try JSONDecoder().decode(Wrapper.self, from: json)
            #expect(w.register == expected)
        }
    }

    @Test func decode_unknownValue_fallsBackToCasual() throws {
        struct Wrapper: Decodable { let register: CoachRegister }
        let json = #"{"register":"shakespearean"}"#.data(using: .utf8)!
        let w = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(w.register == .casual)
    }

    @Test func resolve_roundTripsEachValue() {
        for r in CoachRegister.allCases {
            #expect(CoachRegister.resolve(stored: r.rawValue) == r)
        }
    }

    @Test func resolve_missingOrUnknown_defaultsToCasual() {
        #expect(CoachRegister.resolve(stored: nil) == .casual)
        #expect(CoachRegister.resolve(stored: "") == .casual)
        #expect(CoachRegister.resolve(stored: "   ") == .casual)
        #expect(CoachRegister.resolve(stored: "bogus") == .casual)
    }

    @Test func titles_areChineseLabels() {
        #expect(CoachRegister.casual.title == "口语")
        #expect(CoachRegister.neutral.title == "中性")
        #expect(CoachRegister.formal.title == "正式")
        #expect(CoachRegister.academic.title == "学术")
    }
}
